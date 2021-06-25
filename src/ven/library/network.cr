require "http"

module Ven
  class Network < Suite::Extension
    include Suite

    # Contains a reference to a funlet (you can think of
    # it as a callback in this particular case) and an HTTP
    # server. The funlet is needed to re-create the server
    # if it was closed.
    alias Server = {Machine::Funlet, HTTP::Server}

    # Makes a new HTTP::Server. The server will call *funlet*
    # to process the requests.
    private macro create_server(funlet)
      %funlet = {{funlet}}

      HTTP::Server.new do |context|
        # %funlet should expect: path, verb, request body
        # (or empty string).
        output = %funlet.call([
          Str.new(context.request.path).as(Model),
          Str.new(context.request.method).as(Model),
          Str.new((context.request.body.try(&.gets_to_end) || "").to_s).as(Model)
        ])
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
          {funlet = machine.funlet(callback), create_server(funlet)}
        end

        defbuiltin "listen", handle : MNative(Server), port : Num do
          funlet, server = handle.value
          # Automatically recreate the server if this is not
          # the first `listen` for *server*.
          server = create_server(funlet) if server.closed?
          server.bind_tcp(port.to_i)
          # For the SIGINT trap to work, we have to enable fast
          # interrupts.
          Signal::INT.trap do
            server.close
          end
          server.listen unless server.closed?
        end
      end
    end
  end
end
