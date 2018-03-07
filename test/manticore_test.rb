require 'manticore'

# Usage: ruby manticore_test.rb URL [TRUSTSTORE_PATH]
# Example: ruby manticore_test.rb https://tlsv12-elb.aptible-test-grumpycat.com
# Example: ruby manticore_test.rb https://localhost:4433 /tmp/certs/jerry.jks

URL, TRUSTSTORE_PATH = ARGV
if TRUSTSTORE_PATH
  options = { :ssl => { :truststore => TRUSTSTORE_PATH,
                        :truststore_password => "testpass",
                        :truststore_type => "JKS" }}
else
  options = {}
end

client = Manticore::Client.new(options)
response = client.get(URL)
puts response.body
