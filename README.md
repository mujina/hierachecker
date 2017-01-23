# Hiera Checker

Courtesy of [Pugme Ltd](pugme.co.uk)

Hierachecker is a Ruby script for testing Hiera resolution indpendently of Puppet. 

It is released under the Apache 2.0 License. 

## Quick Start

    gem install bundle
    bundle install
    ./hierachecker.rb

## Standard Start

The program is structured around a common precedence hierarchy of environments, roles and client configs, though Hierachecker should work for any precedence hierarchy you have adopted. 

To get running with hierachecker, after setup you need to,

* Create some tests
* Create global facts (optional)
* Clone your hieradata 

### Setup

Make sure you have a Ruby 1.9+ installed. Personally I prefer to install Ruby using [RVM](rvm.io) and then create a new Gemset for Hierachecker

    rvm gemset create hierachecker
    rvm use ruby@hierachecker 
  
First install the [Bundle](bundler.io) Gem and run bundle install to satisfy Gem depenedencies.

    gem install bundle
    bundle install

### Test Creation

Tests are written in YAML. They have the following format 

    <hiera_key>:
      assert: type e.g. String
      facts: Hash
      clientcert: 
        <fqdn>:
          assert: type e.g. Array
          facts: Hash

The hiera_key is the value you are attempting to resolve. 

Assertions can be any type. If you are simply comparing a string 

     assert: "size=5"
    
Or, the value is an array 

    assert: 
      "sizes"
        - 5
        - 6

The facts key is used to pass facts. Perhaps your hieradata contains memory: "size=#{::size}". The facts Hash allows you to assert this correctly.

    facts: 
      "size": 5


The clientcert key accepts a Hash of client specific configs, using the same keys as described above. This allows you to override assertions on a per client basis to reflect your hiera config data. 

In the following example, servers that belong to the web role have a fixed memory allocation set by the ::size fact, which has a value of 4. However web3 has double this memory. A test for this scenario would be as follows:

    memory:
      assert: "size=4"
      facts:
        size: "4"
      clientcert: 
        web3: 
          assert: "size=8
          facts: 
            cpu: "2" # Optional fact


Your Hiera data might look like this 

    roles/web.yaml  # memory: "size=#{::size}"
    nodes/web3.yaml # memory: "size=8"

Role level assertions are optional as are facts. If a fact is set at the role level, this will apply to all clientcerts unless a fact of the same name overrides it. 

Client level assertions are mandatory, on the basis that there is no justification for having a client cert record without it. 

Hieracheck is bundled with some example tests, please take a look at these for further clarification on usage as required. 

### Hiera YAML config 

You can use or customise the existing hiera.yaml config in the root directory of Hierachecker or point to your own hiera.yaml as follows. 

    ./hierachecker.rb --hierayaml /path/to/hiera.yaml
    
Set in config.json 

    { 
      "hiera_yaml": "/home/mujina/hiera.yaml",
      ...
    }
 
You should update :datadir: to reflect the location of your cloned hieradata. 

You may also want to change the :merge_behavior: from 'native' to 'deep' or 'deeper' to reflect your current setup. Using the deep merge options requires the deep_merge Gem which is in the Gemfile. If you're only using native feel free to remove this depedency.

### Limitations, Follow Ups and Contributing

Hierchecker works by creating a scope to satisfy the hierarchy defined in hiera.yaml. At present the dynamic variables defined in hiera.yaml that make up the keys of this scope are hardcoded, so only the following keys may be used. 

  environment: environment
  role: ::role
  clientcert: clientcert

This limitation will be overcome in a later version. For example ::fqdn, trusted.certname and clientcert should all be suitable alternative keys for clientcert. 

I developed this script to allow me to test the Hiera config prior to a production platform migration. I didn't want to be debugging Hiera config on migration night. If you want to help develop it further contact me mujina@animate-it.org or raise a pull request. 
