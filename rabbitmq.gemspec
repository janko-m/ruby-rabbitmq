
Gem::Specification.new do |s|
  s.name          = 'rabbitmq'
  s.version       = '0.0.1'
  s.date          = '2015-05-29'
  s.summary       = "rabbitmq"
  s.description   = "A Ruby RabbitMQ client library based on FFI bindings for librabbitmq."
  s.authors       = ["Joe McIlvain"]
  s.email         = 'joe.eli.mac@gmail.com'
  
  s.files         = Dir["{lib}/**/*.rb", "bin/*", "LICENSE", "*.md"]
  
  s.require_path  = 'lib'
  s.homepage      = 'https://github.com/jemc/rabbitmq/'
  s.licenses      = 'MIT'
  
  s.add_dependency 'ffi', '~> 1.9'
  
  s.add_development_dependency 'bundler',   '~>  1.6'
  s.add_development_dependency 'rake',      '~> 10.3'
  s.add_development_dependency 'pry',       '~>  0.9'
  s.add_development_dependency 'rspec',     '~>  3.0'
  s.add_development_dependency 'rspec-its', '~>  1.0'
  s.add_development_dependency 'fivemat',   '~>  1.3'
end