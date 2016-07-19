require 'sfn-lambda'

module Sfn
  class Callback
    class Lambda < Callback

      def quiet
        ENV['DEBUG']
      end

      def after_config(*_)
        SfnLambda.control.callback = self
        SfnLambda.control.discover_functions!
      end

    end
  end
end
