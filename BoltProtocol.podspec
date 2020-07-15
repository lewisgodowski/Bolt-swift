Pod::Spec.new do |s|

  s.name         = "BoltProtocol"
  s.module_name  = 'Bolt'
  s.version      = "5.2.0"
  s.summary      = "Bolt protocol implementation in Swift"

  s.description  = <<-DESC
The Bolt network protocol is a highly efficient, lightweight client-server protocol designed for database applications.

The reference implementation can be found [here](https://github.com/neo4j-contrib/boltkit). This codebase is the Swift implementation, and is used by [Theo, the Swift Neo4j driver](https://github.com/Neo4j-Swift/Neo4j-Swift).
DESC

  s.homepage     = "https://github.com/Neo4j-Swift/Bolt-swift"

  s.authors            = { "Niklas Saers" => "niklas@saers.com" }
  s.social_media_url   = "http://twitter.com/niklassaers"

  s.license      = { :type => "BSD", :file => "LICENSE" }

  s.ios.deployment_target = "12.2"
  s.osx.deployment_target = "10.14"
  s.tvos.deployment_target = "12.0"

  s.source       = { :git => "https://github.com/Neo4j-Swift/bolt-swift.git", :tag => "#{s.version}" }
  s.source_files  = "Sources"

  s.dependency 'PackStream', '~> 1.1.2'
  s.dependency 'SwiftNIO', '~> 2.19.0'
  s.dependency 'SwiftNIOSSL', '~> 2.8.0'
  s.dependency 'SwiftNIOTransportServices', '~> 1.7.0'
  s.swift_version = '5.2'
end
