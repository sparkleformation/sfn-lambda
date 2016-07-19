class SparkleFormation
  module SparkleAttribute
    module Aws

      def _lambda(*fn_args)
        if(fn_args.size > 2)
          fn_name, fn_uniq_name, fn_opts = fn_args
        else
          fn_name, fn_uniq_name = fn_args
        end
        __t_stringish(fn_name)
        __t_stringish(fn_uniq_name) unless fn_uniq_name.is_a?(::NilClass)
        if(fn_opts)
          fn_runtime = fn_opts[:runtime] if fn_opts[:runtime]
        end
        unless(fn_runtime.is_a?(::NilClass))
          __t_stringish(fn_runtime)
        end
        lookup = ::SfnLambda.control.get(fn_name, fn_runtime)
        new_fn = _dynamic(:aws_lambda_function,
          [fn_name, fn_uniq_name].compact.map(&:to_s).join('_'),
          :resource_name_suffix => :lambda_function
        )
        new_fn.properties.handler lookup[:runtime]
        new_fn.properties.function_name fn_name
        content = ::SfnLambda.control.format_content(lookup)
        if(content[:raw])
          new_fn.properties.zip_file content[:raw]
        else
          new_fn.properties.s3_bucket content[:bucket]
          new_fn.properties.s3_key content[:key]
          if(content[:version])
            new_fn.properties.s3_object_version content[:version]
          end
        end
        new_fn
      end
      alias_method :lambda!, :_lambda

    end
  end
end
