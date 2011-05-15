require 'eventmachine'
require 'ostruct'

module Anisoptera
  
  class DeferrableBody
    include EventMachine::Deferrable

    def call(body)
      body.each do |chunk|
        @body_callback.call(chunk)
      end
    end

    def each &blk
      @body_callback = blk
    end

  end

  class EndPoint

    # This is a template async response.
    AsyncResponse = [-1, {}, []].freeze

    STATUSES = {
      0   => 200,
      1   => 404
    }

    HEADERS = {
      'Cache-Control'   => 'public, max-age=3153600'
    }.freeze

    def initialize(config, &block)
      @config = config
      @handler = block
    end

    def call(env)

      params = routing_params(env)

      body = DeferrableBody.new

      job = Anisoptera::Commander.new( @config.base_path )

      convert = @handler.call(job, params)

      EventMachine::next_tick { env['async.callback'].call [-1, {'Content-Type' => convert.mime_type}, body] }

      EM.system( convert.command ){ |output, status| 
        http_status = STATUSES[status.exitstatus]
        headers = HEADERS.dup.update('Content-Type' => convert.mime_type)
        env['async.callback'].call [http_status, headers, body]
        r = http_status == 200 ? output : 'NOT FOUND'
        body.call [r]
        body.succeed
      }

      AsyncResponse
    end
    
    private
    
    # Borrowed from Dragonfly
    #
    def routing_params(env)
      env['rack.routing_args'] ||
        env['action_dispatch.request.path_parameters'] ||
        env['router.params'] ||
        env['usher.params'] ||
        env['dragonfly.params'] ||
        raise(ArgumentError, "couldn't find any routing parameters in env #{env.inspect}")
    end

  end
  
end