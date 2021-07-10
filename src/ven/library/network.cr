require "http"

module Ven
  class Network < Suite::Extension
    include Suite

    # Contains a reference to a funlet (you can think of
    # it as a callback in this particular case) and an HTTP
    # server. The funlet is needed to re-create the server
    # if it was closed.
    alias Server = {MFrozenLambda, HTTP::Server}

    # Makes a new HTTP::Server. The server will call *callback*,
    # and wait until it processes the request.
    private macro create_server(callback)
      %callback = {{callback}}

      HTTP::Server.new do |context|
        # %callback should expect: path, verb, request body
        # (or empty string).
        output = %callback.call(
          Str.new(context.request.path),
          Str.new(context.request.method),
          Str.new((context.request.body.try(&.gets_to_end) || "").to_s)
        )
        if output.is_a?(Vec)
          # Expected output:
          #   0 status code,
          #   1 response body (string)
          #   2 content type [optional]
          if output.size >= 2
            context.response.status_code = output[0].to_num.to_i
            context.response.output.print output[1].to_str.value
            context.response.content_type = "text/plain"
          end
          if output.size >= 3
            context.response.content_type = output[2].to_str.value
          end
        end
      end
    end

    on_load do
      definternal "http" do |this|
        # Creates a new HTTP server. The server will rely on
        # *callback* to process the requests.
        defbuiltin "new", callback : MLambda do
          {cb = callback.freeze(machine), create_server(cb)}
        end

        # Makes *handle* listen on *uri*.
        defbuiltin "listen", handle : MNative(Server), uri : Str do
          cb, server = handle.value
          # Re-create the server if this is not the first
          # `listen` for it.
          server = create_server(cb) if server.closed?
          server.bind(uri.value)
          # Have a graceful SIGINT.
          Signal::INT.trap do
            server.close
          end
          server.listen unless server.closed?
        end
      end
    end
  end
end
