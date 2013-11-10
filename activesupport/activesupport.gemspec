version = File.read(File.expand_path("../../RAILS_VERSION", __FILE__)).chomp

Gem::Specification.new do |s|
  s.name = 'activesupport'
  s.version = version
  s.summary = 'Support and utility classes used by the Rails framework.'
  s.description = 'Utility library which carries commonly used classes and goodies from the Rails framework'

  s.author = 'David Heinemeier Hansson'
  s.email = 'david@loudthinking.com'
  s.homepage = 'http://www.rubyonrails.org'

  s.require_path = 'lib'

  s.add_dependency('i18n',       '~> 0.6', '>= 0.6.4')
  s.add_dependency('multi_json', '~> 1.0')
end
