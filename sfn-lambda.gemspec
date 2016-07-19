Gem::Specification.new do |s|
  s.name = 'sfn-lambda'
  s.version = '0.1.0'
  s.summary = 'AWS Lambda integration for SparkleFormation'
  s.author = 'Chris Roberts'
  s.email = 'chrisroberts.code@gmail.com'
  s.homepage = 'http://github.com/spox/sfn-lambda'
  s.description = 'AWS Lambda integration for SparkleFormation'
  s.license = 'MIT'
  s.require_path = 'lib'
  s.add_runtime_dependency 'sparkle_formation', '>= 2.1.0'
  s.files = Dir['{lib,docs}/**/*'] + %w(sfn-lambda.gemspec README.md CHANGELOG.md LICENSE)
end
