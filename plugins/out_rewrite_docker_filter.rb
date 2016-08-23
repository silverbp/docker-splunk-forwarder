require 'json'

class Fluent::RewriteTagFilterOutput < Fluent::Output
  Fluent::Plugin.register_output('rewrite_docker_filter', self)

  # Define `log` method for v0.10.42 or earlier
  unless method_defined?(:log)
    define_method("log") { $log }
  end

  def initialize
    super
    require 'string/scrub' if RUBY_VERSION.to_f < 2.1
  end

  def configure(conf)
    super
  end

  def emit(tag, es, chain)
    es.each do |time,record|
      rewrited_tag = rewrite_tag_and_record(tag, record)
      next if rewrited_tag.nil? || tag == rewrited_tag
      Fluent::Engine.emit(rewrited_tag, time, record)
    end

    chain.next
  end

  def rewrite_tag_and_record(tag, record)
    docker_hash = record['docker']
    if docker_hash and docker_hash['name']
      new_tag = 'docker.' + docker_hash['name']

      record['_timestamp'] = record['time']
      begin
        json_message = JSON.parse(record['log'])
        record.merge!(json_message)
        if record['msg']
          record['message'] = record['msg']
        end
        if record['time']
          record['_timestamp'] = record['time']
        end
      rescue Exception => error
        record['message'] = record['log']
      end

      record.reject!{ |k| k == 'msg' || k == 'log' || k == 'time' }

      return new_tag
    end

    return tag
  end

end

