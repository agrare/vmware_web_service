require 'handsoap'
require 'rbvmomi'

module VMwareWebService
  module HandsoapStub
    class Service < Handsoap::Service
      def initialize(ep)
        super

        uri = ep[:uri]
        uri = URI.parse(uri) unless uri.kind_of?(URI)

        require 'rbvmomi/vim'
        @vim = RbVmomi::VIM.new(:host => uri.host, :port => uri.port, :insecure => true, :ssl => uri.scheme == "https", :ns => @ns["n1"], :path => "/sdk", :rev => "8.0")
      end

      def dispatch(doc, action)
        args = xml_doc_to_rbvmomi(doc, action)
        this = args.delete("_this")
        this.send(action.to_sym, args)
      end

      private

      def xml_doc_to_rbvmomi(doc, action)
        method = doc.find(action)
        args   = method.instance_variable_get(:@children)
        args.to_h do |child|
          argument_name  = child.instance_variable_get(:@node_name)
          argument_value = xml_to_rbvmomi(child)

          [argument_name, argument_value]
        end
      end

      def xml_to_rbvmomi(xml)
        # TODO handle more than ManagedObjects

        managed_object_type  = xml.instance_variable_get(:@attributes)&.dig("type")
        name  = xml.instance_variable_get(:@node_name)
        value = xml.instance_variable_get(:@children).first.to_s

        if managed_object_type
          RbVmomi::VIM.const_get(managed_object_type).new(@vim, value)
        else
          value
        end
      end

      def rbvmomi_to_vim_type(obj)
        case obj
        when String
          obj
        when Array
          obj.map { |i| rbvmomi_to_vim_type(i) }
        when RbVmomi::BasicTypes::ManagedObject
          VimString.new(obj._ref, obj.class.wsdl_name, :ManagedObjectReference)
        when RbVmomi::BasicTypes::Base
          VimHash.new(obj.class.wsdl_name).tap do |vim|
            obj.props.each do |key, val|
              vim.send("#{key}=", rbvmomi_to_vim_type(val))
            end
          end
        when String, Symbol, Integer, Time, TrueClass, FalseClass, NillClass
          obj
        else
          raise ArgumentError, "Invalid type #{obj.class}"
        end
      end

      def vim_type_to_rbvmomi(obj)
        case obj
        when Array
          obj.map { |i| vim_to_rbvmomi_types(i) }
        when VimHash
          klass = "RbVmomi::VIM::#{obj.xsiType}".constantize
          klass.new.tap do |new_obj|
            obj.each do |key, val|
              new_obj.send("#{key}=", vim_to_rbvmomi_types(val))
            end
          end
        when VimString
          if obj.xsiType == "ManagedObjectReference"
            klass = "RbVmomi::VIM::#{obj.vimType}".constantize
            klass.new(vim, obj.to_s)
          else
            obj.to_s
          end
        when String, Symbol, Integer, Time, TrueClass, FalseClass, NillClass
          obj
        else
          raise ArgumentError, "Invalid type #{obj.class}"
        end
      end
    end
  end
end
