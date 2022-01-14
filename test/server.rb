#!/usr/bin/env ruby
require 'socket'
require 'thread'

Thread.abort_on_exception = true

PORT = Integer(ENV.fetch('UPSTREAM_PORT', '9200'))
RESPONSE = File.read(
  File.join(
    ENV.fetch('BATS_TEST_DIRNAME'),
    'responses',
    ENV.fetch('UPSTREAM_RESPONSE', 'response.txt')
  )
)
OUTPUT = ENV.fetch('UPSTREAM_OUT', "/tmp/response.log")

puts "Logging to #{OUTPUT}"

out = File.new(OUTPUT, 'w')

server = TCPServer.new(PORT)
mutex = Mutex.new

loop do
  Thread.start(server.accept) do |client|
    begin
      loop do
        lines = []
        client.each_line do |l|
          # We break at the first CRLF, which is the end of headers.
          lines << l
          break if l == "\r\n"
        end
        mutex.synchronize do
          lines.each { |l| out.write(l) }
          out.flush
        end
        client.print(RESPONSE)
      end
    rescue Errno::EPIPE
      # No-op
    ensure
      client.close
    end
  end
end
