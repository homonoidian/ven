require "http"

module Ven
  class Network < Suite::Extension
    include Suite

    # A handler callback together with an `HTTP::Server`.
    alias Server = {MFrozenLambda, HTTP::Server}

    # Creates an `HTTP::Server`. The server will produce a
    # response for an incoming request depending on the return
    # value of `MFrozenLambda` *callback*:
    #
    # - type vec [status-code, response-body]
    # - type vec [status-code, response-body, content-type]
    #
    # *callback* may choose to receive the following arguments
    # (passed in this order):
    #
    # - path (e.g., `"/path/to/foo/bar"`)
    # - verb (e.g., `"GET"`)
    # - request-body (or empty string)
    macro create_server(callback)
      %callback = {{callback}}

      HTTP::Server.new do |context|
        response = %callback.call(
          Str.new(context.request.path),
          Str.new(context.request.method),
          Str.new(context.request.body.try(&.gets_to_end) || "")
        )

        if response.is_a?(Vec)
          if response.size >= 2
            context.response.status_code = response[0].to_num.to_i
            context.response.output.print response[1].to_str.value
            context.response.content_type = "text/plain"
          end
          if response.size >= 3
            context.response.content_type = response[2].to_str.value
          end
        end
      end
    end

    on_load do
      definternal "http" do
        # Creates an HTTP server. The server will produce a
        # response for an incoming request depending on the
        # return value of *callback*. See `create_server`.
        defbuiltin "new", callback : MLambda do
          frozen = callback.freeze(machine)
          server = create_server(frozen)
          MNative(Server).new({frozen, server}, "http server")
        end

        # Binds *server* to *uri*, and starts responding to
        # incoming requests.
        defbuiltin "listen", server : MNative(Server), uri : Str do
          callback, native_server = server.value

          # If the native server is closed (maybe the interrupted
          # error was caught and the user is trying to restart),
          # recreate.
          native_server = create_server(callback) if native_server.closed?
          native_server.bind(uri.value)

          interrupt = Channel(Bool).new

          # Send an interrupt signal down from the server listen
          # up over here, so we can handle it appropriately.
          Signal::INT.trap do
            native_server.close
            interrupt.send(true)
          end

          # Have two fibers: one that runs the server, and
          # another blocking until an interrupt of some kind,
          # graceful or not.
          spawn native_server.listen

          if interrupt.receive
            machine.die("interrupted")
          end
        end
      end
    end
  end
end
