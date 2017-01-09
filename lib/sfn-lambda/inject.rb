class SparkleFormation
  module SparkleAttribute
    module Aws

      def _lambda(*fn_args, &block)
        if(fn_args.size > 2)
          fn_name, fn_uniq_name, fn_opts = fn_args
        else
          fn_name, fn_uniq_name = fn_args
          fn_opts = Smash.new
        end
        __t_stringish(fn_name)
        __t_stringish(fn_uniq_name) unless fn_uniq_name.is_a?(::NilClass)

        fn_runtime = fn_opts[:runtime] if fn_opts[:runtime]

        unless(fn_runtime.is_a?(::NilClass))
          __t_stringish(fn_runtime)
        end
        lookup = ::SfnLambda.control.get(fn_name, fn_runtime)
        new_fn = _dynamic(:aws_lambda_function,
          [fn_name, fn_uniq_name].compact.map(&:to_s).join('_'),
          :resource_name_suffix => :lambda_function
        )
        new_fn.properties.handler fn_name
        new_fn.properties.runtime lookup[:runtime]
        content = ::SfnLambda.control.format_content(lookup)
        if(content[:raw])
          new_fn.properties.code.zip_file content[:raw]
        else
          new_fn.properties.code.s3_bucket content[:bucket]
          new_fn.properties.code.s3_key content[:key]
          if(content[:version])
            new_fn.properties.code.s3_object_version content[:version]
          end
        end
        if(fn_opts[:role])
          new_fn.properties.role fn_opts[:role]
        end
        if(block)
          new_fn.instance_exec(new_fn, &block)
        end
        new_fn
      end
      alias_method :lambda!, :_lambda

    end
  end
end
