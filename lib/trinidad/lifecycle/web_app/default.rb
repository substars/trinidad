module Trinidad
  module Lifecycle
    module WebApp
      class Default < Lifecycle::Base
        include Shared
        
        def configure(context)
          super
          configure_default_servlet(context)
          deployment_descriptor = configure_deployment_descriptor(context)
          unless deployment_descriptor
            configure_rack_servlet(context)
            configure_rack_listener(context)
          end
          configure_context_params(context)
          configure_context_loader(context)
        end
        
        def before_init(event)
          super
          set_context_xml event.lifecycle
          # AFTER_INIT_EVENT ContextConfig#init() will pick this up
        end
        
        protected
        
        @@_add_context_config = true # due backward compatibility
        
        def configure_deployment_descriptor(context)
          if descriptor = web_app.deployment_descriptor
            listeners = context.findLifecycleListeners
            context_config = listeners && listeners.find do |listener|
              listener.is_a?(Trinidad::Tomcat::ContextConfig)
            end

            if context_config.nil?
              if @@_add_context_config
                context_config = Trinidad::Tomcat::ContextConfig.new
                context.addLifecycleListener(context_config)
              else
                raise "initialized context is missing a ContextConfig listener"
              end
            end

            context_config.setDefaultWebXml(descriptor)
          end
          descriptor
        end

        def configure_rack_servlet(context)
          wrapper = context.create_wrapper
          rack_servlet = web_app.rack_servlet
          if rack_servlet[:instance]
            wrapper.servlet = rack_servlet[:instance]
          else
            wrapper.servlet_class = rack_servlet[:class]
            wrapper.async_supported = rack_servlet[:async_supported]
            wrapper.load_on_startup = rack_servlet[:load_on_startup]
            add_init_params wrapper, rack_servlet[:init_params]
          end
          name = wrapper.name = rack_servlet[:name]

          context.add_child(wrapper)
          add_servlet_mapping(context, rack_servlet[:mapping], name)
        end

        def configure_rack_listener(context)
          unless web_app.rack_servlet[:instance]
            context.add_application_listener(web_app.rack_listener)
          end
        end

        def configure_context_params(context)
          web_app.context_params.each do |name, value|
            context.add_parameter(name, value)
          end
        end
        # @deprecated use {#configure_context_params}
        alias_method :configure_init_params, :configure_context_params

        def configure_context_loader(context)
          class_loader = web_app.class_loader

          add_application_jars(class_loader)
          add_application_java_classes(class_loader)

          loader = Trinidad::Tomcat::WebappLoader.new(class_loader)
          context.loader = loader # does loader.container = context
        end

        def add_application_jars(class_loader)
          return unless web_app.libs_dir

          resources_dir = File.join(web_app.web_app_dir, web_app.libs_dir, '**', '*.jar')

          Dir[resources_dir].each do |resource|
            class_loader.addURL(java.io.File.new(resource).to_url)
          end
        end

        def add_application_java_classes(class_loader)
          return unless web_app.classes_dir

          resources_dir = File.join(web_app.web_app_dir, web_app.classes_dir)
          class_loader.addURL(java.io.File.new(resources_dir).to_url)
        end
        
        def set_context_xml(context)
          # behave similar to a .war - checking /META-INF/context.xml on CP
          context_xml = web_app.context_xml
          context_xml = 'META-INF/context.xml' if context_xml.nil?
          if context_xml
            # NOTE: make it absolute to ContextConfig to not use a baseDir :
            unless java.io.File.new(context_xml).isAbsolute
              if web_app.classes_dir
                context_xml = File.join(web_app.classes_dir, context_xml)
              end
              context_xml = 
                File.expand_path(File.join(web_app.web_app_dir, context_xml))
            end
            context.setDefaultContextXml(context_xml)
          end
        end
        
        def configure_default_servlet(context)
          default = Trinidad::WebApp::DEFAULT_SERVLET_NAME
          default_wrapper = context.find_child(default)
          case default_servlet = web_app.default_servlet
          when true
            # nothing to do leave default as is
          when false
            # use the one from web.xml - remove what Tomcat set-up
            remove_servlet_mapping(context, default)
            context.remove_child(default_wrapper)
            false
          else
            wrapper, name = default_wrapper, default
            if servlet = default_servlet[:instance]
              wrapper = context.create_wrapper
              wrapper.name = name = default_servlet[:name] || default
              wrapper.servlet = servlet
              context.remove_child(default_wrapper)
              context.add_child(wrapper) # the new 'default' servlet
            elsif servlet_class = default_servlet[:class]
              wrapper.servlet_class = servlet_class
            end
            # do not remove wrapper but only "update" the default :
            wrapper.load_on_startup = ( default_servlet[:load_on_startup] || 
                default_wrapper.load_on_startup ).to_i
            add_init_params(wrapper, default_servlet[:init_params])
            # NOTE: we keep the root mapping / should not hurt ?
            if mapping = default_servlet[:mapping]
              add_servlet_mapping(context, mapping, name)
              # else keep the servlet mapping as is ...
            end
            wrapper
          end
        end
        
        private
        
        def add_servlet_mapping(context, mapping, name)
          if mapping.is_a?(String) || mapping.is_a?(Symbol) 
            context.add_servlet_mapping(mapping.to_s, name)
          else
            mapping.each { |m| add_servlet_mapping(context, m, name) }
          end
        end

        def add_init_params(wrapper, params)
          return unless params
          params.each do |param, value|
            val = value.to_s unless value.nil?
            wrapper.add_init_parameter(param.to_s, val)
          end
        end
        
      end
    end
    Default = Trinidad::Lifecycle::WebApp::Default # backwards compatibility
  end
end
