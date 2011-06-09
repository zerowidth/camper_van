module CamperVan
  class HandlerMissing < StandardError
    attr_reader :command
    def initialize(command)
      @command = command
      @message = "no handler for the #{command.keys.first} command"
    end
  end

  module CommandDefinition

    def self.included(base)
      base.module_eval { include InstanceMethods }
      base.extend ClassMethods
    end

    module ClassMethods

      # Public: defines a handler for the given irc command
      #
      # command - the irc command to define a handler for
      #
      # Example:
      #
      #   handle :nick do |args|
      #     # ... change nickname to ...
      #   end
      #
      # ```
      # def handle_nick(*args)
      #   # contents of block
      # end
      # ```
      def handle(command, &block)
        define_method "handle_#{command}".to_sym, &block
      end
    end

    module InstanceMethods

      # Public: handles the given command using the handler method
      # defined by the class-level handler metaprogramming, if it
      # exists.
      #
      # command - the Hash command as provided by the irc command parser
      #
      # Example:
      #
      #   handle :nick => ["joe"]
      #
      # Raises CamperVan::HandlerMissing if there is no handler method
      #   defined for the given command.
      def handle(command)
        name, args = command.to_a.first
        method_name = "handle_#{name}".to_sym
        if self.respond_to? method_name
          m = method(method_name)
          if m.arity > 0
            send method_name, args
          else
            send method_name
          end
        else
          raise CamperVan::HandlerMissing, command
        end
      end
    end

  end
end
