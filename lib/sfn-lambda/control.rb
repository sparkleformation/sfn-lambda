require 'singleton'

module SfnLambda

  # @return [Control]
  def self.control
    Control.instance
  end

  class Control

    include Singleton

    DEFAULTS = {
      :INLINE_MAX_SIZE => 4096,
      :INLINE_RESTRICTED => ['java8'].freeze,
      :BUILD_REQUIRED => {
        'java8' => {
          :build_command => 'mvn package',
          :output_directory => './target',
          :asset_extension => '.jar'
        }.freeze
      }.freeze
    }.freeze

    attr_reader :functions
    attr_accessor :callback

    # Create a new control instance
    #
    # @return [self]
    def initialize
      @functions = Smash.new
    end

    # @return [Array<String>] paths to lambda storage directories
    def lambda_directories
      paths = [callback.config.fetch(:lambda, :directory, 'lambda')].flatten.compact.uniq.map do |path|
        File.expand_path(path)
      end
      invalids = paths.find_all do |path|
        !File.directory?(path)
      end
      unless(invalids.empty?)
        raise "Invalid lambda directory paths provided: #{invalids.join(', ')}"
      end
      paths
    end

    # Get path to lambda function
    #
    # @param name [String] name of lambda function
    # @param runtime [String] runtime of lambda function
    # @return [Hash] {:path, :runtime}
    def get(name, runtime=nil)
      unless(runtime)
        runtime = functions.keys.find_all do |r_name|
          functions[r_name].keys.include?(name.to_s)
        end
        if(runtime.empty?)
          raise "Failed to locate requested lambda function `#{name}`"
        elsif(runtime.size > 1)
          raise "Multiple lambda function matches for `#{name}`. (In runtimes: `#{runtime.sort.join('`, `')}`)"
        end
        runtime = runtime.first
      end
      result = functions.get(runtime, name)
      if(result.nil?)
        raise "Failed to locate requested lambda function `#{name}`"
      else
        Smash.new(:path => result, :runtime => runtime, :name => name)
      end
    end

    # Format lambda function content to use within template. Will provide raw
    # source when function can be inlined within the template. If inline is not
    # available, it will store within S3
    #
    # @param info [Hash] content information
    # @option info [String] :path path to lambda function
    # @option info [String] :runtime runtime of lambda function
    # @option info [String] :name name of lambda function
    # @return [Smash] content information
    def format_content(info)
      if(can_inline?(info))
        Smash.new(:raw => File.read(info[:path]))
      else
        apply_build!(info)
        key_name = generate_key_name(info)
        io = File.open(info[:path], 'rb')
        file = bucket.files.build
        file.name = key_name
        file.body = io
        file.save
        io.close
        if(versioning_enabled?)
          result = s3.request(
            :path => s3.file_path(file),
            :endpoint => s3.bucket_endpoint(file.bucket),
            :method => :head
          )
          version = result[:headers][:x_amz_version_id]
        end
        Smash(:bucket => storage_bucket, :key => key_name, :version => version)
      end
    end

    # Build the lambda asset if building is a requirement
    #
    # @param info [Hash]
    # @return [TrueClass, FalseClass] build was performed
    def apply_build!(info)
      if(build_info = self[:build_required][info[:runtime]])
        Open3.popen3(build_info[:build_command], :chdir => info[:path]) do |stdin, stdout, stderr, wait_thread|
          exit_status = wait_thread.value
          unless(exit_status.success?)
            callback.ui.error "Failed to build lambda assets for storage from path: #{info[:path]}"
            callback.ui.debug "Build command used which generated failure: `#{build_info[:build_command]}`"
            callback.ui.debug "STDOUT: #{stdout.read}"
            callback.ui.debug "STDERR: #{stderr.read}"
            raise "Failed to build lambda asset for storage! (path: `#{info[:path]}`)"
          end
        end
        file = Dir.glob(File.join(info[:path], build_info[:output_directory], "*.#{build_config[:asset_extension]}")).first
        if(file)
          info[:path] = file
          true
        else
          debug "Glob pattern used for build asset detection: `#{File.join(info[:path], build_info[:output_directory], "*.#{build_config[:asset_extension]}")}`"
          raise "Failed to locate generated build asset for storage! (path: `#{info[:path]}`)"
        end
      else
        false
      end
    end

    # @return [Miasma::Models::Storage::Bucket]
    def bucket
      storage_bucket = callback.config.fetch(:lambda, :upload, :bucket, callback.config[:nesting_bucket])
      if(storage_bucket)
        s3 = api.connection.api_for(:storage)
        l_bucket = s3.buckets.get(storage_bucket)
      end
      unless(l_bucket)
        raise "Failed to locate configured bucket for lambda storage (#{storage_bucket})"
      else
        l_bucket
      end
    end

    # @return [TrueClass, FalseClass] bucket has versioning enabled
    def versioning_enabled?
      unless(@versioned.nil?)
        s3 = api.connection.api_for(:storage)
        result = s3.request(
          :path => '/',
          :params => {
            :versioning => true
          },
          :endpoint => s3.bucket_endpoint(bucket)
        )
        @versioned = result.get(:body, 'VersioningConfiguration', 'Status') == 'Enabled'
      end
      @versioned
    end

    # Generate key name based on state
    #
    # @param info [Hash]
    # @return [String] key name
    def generate_key_name(info)
      if(versioning_enabled?)
        "sfn.lambda/#{info[:runtime]}/#{File.basename(info[:path])}"
      else
        checksum = Digest::SHA256.new
        File.open(info[:path], 'rb') do |file|
          while(content = file.read(2048))
            checksum << content
          end
        end
        "sfn.lambda/#{info[:runtime]}/#{File.basename(info[:path])}-#{checksum.base64digest}"
      end
    end

    # Determine if function can be defined inline within template
    #
    # @param info [Hash]
    # @return [TrueClass, FalseClass]
    def can_inline?(info)
      !self[:inline_restricted].include?(info[:runtime]) && File.size(info[:path]) <= self[:inline_max_size]
    end

    # Get configuration value for control via sfn configuration and fall back
    # to defined defaults if not set
    #
    # @return [Object] configuration value
    def [](key)
      callback.config.fetch(:lambda, :config, key.to_s.downcase, DEFAULTS[key.to_s.upcase.to_sym])
    end

    # Discover all defined lambda functions available in directories provided
    # via configuration
    #
    # @return [NilClass]
    def discover_functions!
      core_paths = lambda_directories
      core_paths.each do |path|
        Dir.new(path).each do |dir_item|
          next if dir_item.start_with?('.')
          next unless File.directory?(File.join(path, dir_item))
          if(self[:build_required].keys.include?(dir_item))
            Dir.new(File.join(path, dir_item)).each do |item|
              next if item.start_with?('.')
              full_item = File.join(path, dir_item, item)
              next unless File.directory?(full_item)
              functions.set(dir_item, item, full_item)
            end
          else
            items = Dir.glob(File.join(path, dir_item, '**', '**', '*'))
            items.each do |full_item|
              next unless File.file?(full_item)
              item = full_item.sub(File.join(path, dir_item, ''), '').gsub(File::SEPARATOR, '')
              item = item.sub(/#{Regexp.escape(File.extname(item))}$/, '')
              functions.set(dir_item, item, full_item)
            end
          end
        end
      end
      nil
    end

  end

end
