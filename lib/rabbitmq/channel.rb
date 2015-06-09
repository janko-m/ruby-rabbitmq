
module RabbitMQ
  class Channel
    
    attr_reader :connection
    attr_reader :id
    
    # Don't create a {Channel} directly; call {Connection#channel} instead.
    # @api private
    def initialize(connection, id, pre_allocated: false)
      @connection = connection
      @id         = id
      connection.send(:allocate_channel, id) unless pre_allocated
      
      @finalizer = self.class.send :create_finalizer_for, @connection, @id
      ObjectSpace.define_finalizer self, @finalizer
    end
    
    # Release the channel id to be reallocated to another {Channel} instance.
    # This will be called automatically by the object finalizer after
    # the object becomes unreachable by the VM and is garbage collected,
    # but you may want to call it explicitly if you plan to reuse the same
    # channel if in another {Channel} instance explicitly.
    #
    # @return [Channel] self.
    #
    def release
      if @finalizer
        @finalizer.call
        ObjectSpace.undefine_finalizer self
      end
      @finalizer = nil
      
      self
    end
    
    # @see {Connection#on_event}
    def on(*args, &block)
      @connection.on_event(@id, *args, &block)
    end
    
    # @see {Connection#run_loop!}
    def run_loop!(*args)
      @connection.run_loop!(*args)
    end
    
    # @see {Connection#break!}
    def break!
      @connection.break!
    end
    
    # Create a finalizer not entangled with the {Channel} instance.
    # @api private
    def self.create_finalizer_for(connection, id)
      Proc.new do
        connection.send(:release_channel, id)
      end
    end
    
    private def rpc(request_type, params=[{}], response_type)
      @connection.send_request(@id, request_type, params.last)
      if response_type
        @connection.fetch_response(@id, response_type)
      else
        true
      end
    end
    
    ##
    # Exchange operations
    
    def exchange_declare(name, type, **opts)
      rpc :exchange_declare, [
        exchange:    name,
        type:        type,
        passive:     opts.fetch(:passive,     false),
        durable:     opts.fetch(:durable,     false),
        auto_delete: opts.fetch(:auto_delete, false),
        internal:    opts.fetch(:internal,    false),
      ], :exchange_declare_ok
    end
    
    def exchange_delete(name, **opts)
      rpc :exchange_delete, [
        exchange:  name,
        if_unused: opts.fetch(:if_unused, false),
      ], :exchange_delete_ok
    end
    
    def exchange_bind(source, destination, **opts)
      rpc :exchange_bind, [
        source:      source,
        destination: destination,
        routing_key: opts.fetch(:routing_key, ""),
        arguments:   opts.fetch(:arguments,   {}),
      ], :exchange_bind_ok
    end
    
    def exchange_unbind(source, destination, **opts)
      rpc :exchange_unbind, [
        source:      source,
        destination: destination,
        routing_key: opts.fetch(:routing_key, ""),
        arguments:   opts.fetch(:arguments,   {}),
      ], :exchange_unbind_ok
    end
    
    ##
    # Queue operations
    
    def queue_declare(name, **opts)
      rpc :queue_declare, [
        queue:       name,
        passive:     opts.fetch(:passive,     false),
        durable:     opts.fetch(:durable,     false),
        exclusive:   opts.fetch(:exclusive,   false),
        auto_delete: opts.fetch(:auto_delete, false),
        arguments:   opts.fetch(:arguments,   {}),
      ], :queue_declare_ok
    end
    
    def queue_bind(name, exchange, **opts)
      rpc :queue_bind, [
        queue:       name,
        exchange:    exchange,
        routing_key: opts.fetch(:routing_key, ""),
        arguments:   opts.fetch(:arguments,   {}),
      ], :queue_bind_ok
    end
    
    def queue_unbind(name, exchange, **opts)
      rpc :queue_unbind, [
        queue:       name,
        exchange:    exchange,
        routing_key: opts.fetch(:routing_key, ""),
        arguments:   opts.fetch(:arguments,   {}),
      ], :queue_unbind_ok
    end
    
    def queue_purge(name)
      rpc :queue_purge, [queue: name], :queue_purge_ok
    end
    
    def queue_delete(name, **opts)
      rpc :queue_delete, [
        queue:     name,
        if_unused: opts.fetch(:if_unused, false),
        if_empty:  opts.fetch(:if_empty,  false),
      ], :queue_delete_ok
    end
    
    ##
    # Consumer operations
    
    def basic_qos(**opts)
      rpc :basic_qos, [
        prefetch_count: opts.fetch(:prefetch_count, 0),
        prefetch_size:  opts.fetch(:prefetch_size,  0),
        global:         opts.fetch(:global,         false),
      ], :basic_qos_ok
    end
    
    def basic_consume(queue, consumer_tag="", **opts)
      rpc :basic_consume, [
        queue:        queue,
        consumer_tag: consumer_tag,
        no_local:     opts.fetch(:no_local,  false),
        no_ack:       opts.fetch(:no_ack,    false),
        exclusive:    opts.fetch(:exclusive, false),
        arguments:    opts.fetch(:arguments, {}),
      ], :basic_consume_ok
    end
    
    def basic_cancel(consumer_tag)
      rpc :basic_cancel, [consumer_tag: consumer_tag], :basic_cancel_ok
    end
    
    ##
    # Transaction operations
    
    def tx_select
      rpc :tx_select, [], :tx_select_ok
    end
    
    def tx_commit
      rpc :tx_commit, [], :tx_commit_ok
    end
    
    def tx_rollback
      rpc :tx_rollback, [], :tx_rollback_ok
    end
    
    ##
    # Message operations
    
    def basic_get(queue, **opts)
      rpc :basic_get, [
        queue:  queue,
        no_ack: opts.fetch(:no_ack, false),
      ], [:basic_get_ok, :basic_get_empty]
    end
    
    def basic_ack(delivery_tag, **opts)
      rpc :basic_ack, [
        delivery_tag: delivery_tag,
        multiple:     opts.fetch(:multiple, false),
      ], nil
    end
    
    def basic_nack(delivery_tag, **opts)
      rpc :basic_nack, [
        delivery_tag: delivery_tag,
        multiple:     opts.fetch(:multiple, false),
        requeue:      opts.fetch(:requeue, true),
      ], nil
    end
    
    def basic_reject(delivery_tag, **opts)
      rpc :basic_reject, [
        delivery_tag: delivery_tag,
        requeue:      opts.fetch(:requeue, true),
      ], nil
    end
    
    def basic_publish(body, exchange, routing_key, **opts)
      body        = FFI::Bytes.from_s(body, true)
      exchange    = FFI::Bytes.from_s(exchange, true)
      routing_key = FFI::Bytes.from_s(routing_key, true)
      properties  = FFI::BasicProperties.new.apply(
        content_type:       opts.fetch(:content_type,     "application/octet-stream"),
        content_encoding:   opts.fetch(:content_encoding, ""),
        headers:            opts.fetch(:headers,          {}),
        delivery_mode:     (opts.fetch(:persistent,    false) ? :persistent : :nonpersistent),
        priority:           opts.fetch(:priority,          0),
        correlation_id:     opts.fetch(:correlation_id,   ""),
        reply_to:           opts.fetch(:reply_to,         ""),
        expiration:         opts.fetch(:expiration,       ""),
        message_id:         opts.fetch(:message_id,       ""),
        timestamp:          opts.fetch(:timestamp,         0),
        type:               opts.fetch(:type,             ""),
        user_id:            opts.fetch(:user_id,          ""),
        app_id:             opts.fetch(:app_id,           ""),
        cluster_id:         opts.fetch(:cluster_id,       "")
      )
      
      Util.error_check :"publishing a message",
        FFI.amqp_basic_publish(connection.send(:ptr), @id,
          exchange,
          routing_key,
          opts.fetch(:mandatory, false),
          opts.fetch(:immediate, false),
          properties,
          body
        )
      
      properties.free!
      true
    end
    
  end
end
