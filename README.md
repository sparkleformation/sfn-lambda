# AWS Lambda for SparkleFormation

Lets make lambda functions easier to manage in CloudFormation!

## Design

This SparkleFormation Callback adds a new helper method to AWS based
SparkleFormation templates called `lambda!`. This helper method will
insert an `AWS::Lambda::Function` resource into the template using
source files contained within configured directories.

## Features

* Individual source files for lambda functions
* Automatic resource creation within templates
* Automatic code setup for resource
 * Acceptable functions will be defined inline
 * S3 storage will be used when inline is unacceptable
 * S3 versioning will be used when bucket configured for versioning
 * Automatic asset builds (for `java8` runtime targets)

## Usage

### Setup

First add the `sfn-lambda` gem to the local bundle (in the `./Gemfile`):

```ruby
group :sfn do
  gem 'sfn-lambda'
end
```

Now enable the `sfn-lambda` callback in the `.sfn` configuration file:

```ruby
Configuration.new do
  ...
  callbacks do
    require ['sfn-lambda']
    default ['lambda']
  end
  ...
end
```

_NOTE: If using the `java8` runtime for lambda functions, `maven` must
be installed with `mvn` being available within the user's PATH._

### Configuration

#### Lambda function files directory

By default the `sfn-lambda` callback will search the `./lambda` directory
for lambda function files. A custom directory path can be used by modifying
the configuration:

```ruby
Configuration.new do
  lambda do
    directory './my-lambdas'
  end
end
```

#### S3 lambda function file storage

By default the `sfn-lambda` callback will use the bucket name provided by
the `nesting_bucket` configuration item. This can be customized to use a
different bucket by modifying the configuration:

```ruby
Configuration.new do
  lambda do
    upload do
      bucket 'my-custom-bucket'
    end
  end
end
```

### Lambda function files

The path of lambda function files is important. The path is used to determine
the proper handler for running the lambda function, as well as providing the
identifier to reference the function. The path structure is as follows:

```
./lambda/RUNTIME/FUNCTION_NAME.extension
```

The `RUNTIME` defines the runtime used for handling the lambda function. At
the time of writing this, that value can be one of:

* `nodejs`
* `nodejs4.3`
* `java8`
* `python2.7`

_NOTE: Runtime values are not validated which allows new runtimes to be used
as they are made available._

The `FUNCTION_NAME` is used for two purposes:

1. It identifies the function name lambda should use
2. It is used in combination with the `RUNTIME` to identify the lambda in the template

### Example

Using the python example described within the lambda documentation:

* http://docs.aws.amazon.com/lambda/latest/dg/python-programming-model-handler-types.html

we can define our handler code:

* `./lambda/python2.7/my_function.py`

```python
def my_handler(event, context):
    message = 'Hello {} {}!'.format(event['first_name'], event['last_name'])
    return {
        'message' : message
    }
```

Now, using a new helper method, lambda resources can be created within a SparkleFormation template using
the newly created file:

* `./sparkleformation/lambda_test.rb`

```ruby
SparkleFormation.new(:lambda_test) do
  lambda!(:my_function, :handler => :my_handler)
end
```

If the handler argument is not specified the default value is 'handler'.

```ruby
SparkleFormation.new(:lambda_test) do
  lambda!(:my_function)
end
```

When the template is printed a lambda resource is shown with the function properly inlined:

```
$ sfn print --file lambda_test
{
  "Resources": {
    "MyHandlerLambdaFunction": {
      "Type": "AWS::Lambda::Function",
      "Properties": {
        "Handler": "index.my_handler",
        "Runtime": "python2.7"
        "FunctionName": "my_function",
        "ZipFile": "def my_handler(event, context):\n    message = 'Hello {} {}!'.format(event['first_name'], event['last_name'])\n    return {\n        'message' : message\n    }\n\n"
      }
    }
  }
}
```

If the name of a lambda function is shared across multiple runtimes, the desired runtime
can be specified within the call:

```ruby
SparkleFormation.new(:lambda_test) do
  lambda!(:my_function, :handler => :my_handler, :runtime => 'python2.7')
end
```

If a lambda function is to be used for creating multiple resources within a template, a
custom name can be added as well:

```ruby
SparkleFormation.new(:lambda_test) do
  lambda!(:my_function, :first, :handler => :my_handler, :runtime => 'python2.7')
  lambda!(:my_function, :second, :handler => :my_handler, :runtime => 'python2.7')
end
```

### Special Cases

### S3 Storage

When the size of the lambda function is greater than the defined max size (4096 default),
the function will be stored on S3. If the bucket configured for storage has versioning
enabled, versioning information will be automatically set within the resource. If no
versioning information is available, a checksum will be attached to the generated key name.

### Builds

For lambda functions utilizing the `java8` runtime, the `sfn-lambda` callback will behave
slightly different. When discovering available lambda functions, the directory names under the
`./lambda/java8` directory will be used. This allows for the collection of required files to
be stored within the directory.

Using the example here: http://docs.aws.amazon.com/lambda/latest/dg/java-create-jar-pkg-maven-no-ide.html

The defined directory structure would be:

```
$ cd ./lambda
$ tree
.
|____java8
| |____hello
| | |____src
| | | |____main
| | | | |____java
| | | | | |____example
| | | | | | |____Hello.java
| | |____pom.xml
```

When the `hello` lambda function is used within a template, `sfn-lambda` will automatically generate
the required jar file using Maven and store the resulting asset on S3.

_NOTE: Maven is required to be installed when using the `java8` runtime_

## Info

* Repository: https://github.com/sparkleformation/sfn-lambda
* IRC: Freenode @ #sparkleformation