#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
require 'open-uri'
require 'json'
require 'oj'

class Fluent::DockerToSplunkOutput < Fluent::Output

  SOCKET_TRY_MAX = 3

  Fluent::Plugin.register_output('docker_to_splunk', self)

  include Fluent::SetTagKeyMixin
  config_set_default :include_tag_key, false

  include Fluent::SetTimeKeyMixin
  config_set_default :include_time_key, false

  config_param :host, :string, :default => 'localhost'
  config_param :port, :string, :default => 9997
  config_param :pause, :integer, :default => 1

  # To support log_level option implemented by Fluentd v0.10.43
  unless method_defined?(:log)
    define_method(:log) { $log }
  end

  def configure(conf)
    super
  end

  def start
    super
    log.info("Waiting #{@pause} seconds to give splunk a chance to start up.")
    sleep(@pause)
  end

  def shutdown
    super
    if @splunk_connection && @splunk_connection.respond_to?(:close)
      @splunk_connection.close
    end
  end

  def emit(tag, es, chain)
    chain.next
    es.each {|time,record|
      if record
        formatted_json = format_json(record)
        if formatted_json
          splunk_send(formatted_json)
        end
      end
    }
  end

  # =================================================================

  protected

  def format_json(record)
    to_json = Oj.dump record
  end

  def splunk_send(text, try_count=0)
    log.debug("splunk_send: #{text}")

    successful_send = false
    try_count = 0

    while (!successful_send && try_count < SOCKET_TRY_MAX)
      begin
        unless @splunk_connection
          @splunk_connection = TCPSocket.open(@host, @port)
        end
        @splunk_connection.puts(text)
        successful_send = true

      rescue NoMethodError, Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::EPIPE => se
        log.error("splunk_send - socket send retry (#{try_count}) failed: #{se}")
        try_count = try_count + 1

        successful_reopen = false
        while (!successful_reopen && try_count < SOCKET_TRY_MAX)
          begin
            # Try reopening
            @splunk_connection = TCPSocket.open(@host, @port)
            successful_reopen = true
          rescue Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::EPIPE => se
            log.error("splunk_send - socket open retry (#{try_count}) failed: #{se}")
            try_count = try_count + 1
          end
        end
      end
    end

    if !successful_send
      log.fatal("splunk_send - retry of sending data failed after #{SOCKET_TRY_MAX} chances.")
      log.warn(text)
    end

  end


end
