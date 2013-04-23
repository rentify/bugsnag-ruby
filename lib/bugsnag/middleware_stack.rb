module Bugsnag
  class MiddlewareStack
    def initialize
      @middlewares = []
      @disabled_middleware = []
    end

    def use(new_middleware)
      return if @disabled_middleware.include?(new_middleware)

      @middlewares << new_middleware
    end

    def insert_after(after, new_middleware)
      return if @disabled_middleware.include?(new_middleware)

      index = @middlewares.rindex(after)
      if index.nil?
        @middlewares << new_middleware
      else
        @middlewares.insert index + 1, new_middleware
      end
    end

    def insert_before(before, new_middleware)
      return if @disabled_middleware.include?(new_middleware)

      index = @middlewares.index(before) || @middlewares.length
      @middlewares.insert index, new_middleware
    end

    def disable(*middlewares)
      @disabled_middleware += middlewares

      @middlewares.delete_if {|m| @disabled_middleware.include?(m)}
    end

    # This allows people to proxy methods to the array if they want to do more complex stuff
    def method_missing(method, *args, &block)
      @middlewares.send(method, *args, &block)
    end

    # Runs the middleware stack and calls
    def run(notification)
      # The final lambda is the termination of the middleware stack. It calls deliver on the notification
      lambda_has_run = false
      notify_lambda = lambda do |notification|
        lambda_has_run = true
        yield
      end

      begin
        # We reverse them, so we can call "call" on the first middleware
        middleware_procs.reverse.inject(notify_lambda) { |n,e| e[n] }.call(notification)
      rescue StandardError => e
        # KLUDGE: Since we don't re-raise middleware exceptions, this breaks rspec
        raise if e.class.to_s == "RSpec::Expectations::ExpectationNotMetError"

        # We dont notify, as we dont want to loop forever in the case of really broken middleware, we will
        # still send this notify
        Bugsnag.warn "Bugsnag middleware error: #{e}"
        Bugsnag.warn "Middleware error stacktrace: #{e.backtrace.inspect}"
      end

      # Ensure that the deliver has been performed, and no middleware has botched it
      notify_lambda.call(notification) unless lambda_has_run
    end

    private
    # Generates a list of middleware procs that are ready to be run
    # Pass each one a reference to the next in the queue
    def middleware_procs
      @middlewares.map{|middleware| proc { |next_middleware| middleware.new(next_middleware) } }
    end
  end
end