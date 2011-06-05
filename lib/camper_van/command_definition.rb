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
      def handle(command, &block)
        command_registry[command] = block
      end

      def command_registry
        @command_registry ||= {}
      end
    end

    module InstanceMethods
      def handle(command)
        name, args = command.to_a.first
        if block = self.class.command_registry[name]
          instance_exec(args, &block)
        else
          raise CamperVan::HandlerMissing, command
        end
      end
    end

  end
end
