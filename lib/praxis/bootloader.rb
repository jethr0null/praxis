module Praxis

  class Bootloader

    attr_reader :application
    attr_reader :stages

    def initialize(application)
      @application = application
      @stages = Array.new

      setup_stages!
    end

    def config
      @application.config
    end

    def root
      @application.root
    end

    def setup_stages!
      # Require environment first. they define constants and environment specific settings
      stages << BootloaderStages::Environment.new(:environment, application)

      # then setup plugins
      stages << BootloaderStages::PluginLoader.new(:plugins, application)
      
      # then the initializers. as it is their job to ensure monkey patches and other
      # config is in place first.
      stages << BootloaderStages::FileLoader.new(:initializers, application)

      # then require lib/ code.
      stages << BootloaderStages::FileLoader.new(:lib, application)

      # design-specific code.
      stages << BootloaderStages::SubgroupLoader.new(:design, application)

      # app-specific code.
      stages << BootloaderStages::SubgroupLoader.new(:app, application)

      # setup routing
      stages << BootloaderStages::Routing.new(:routing, application)

      # naggy warning about unloaded files
      stages << BootloaderStages::WarnUnloadedFiles.new(:warn_unloaded_files, application)

      after(:app) do
        Praxis::Mapper.finalize!
        Praxis::Blueprint.finalize!
      end

    end

    def delete_stage(stage_name)
      if (stage = stages.find { |stage| stage.name == stage_name })
        stages.delete(stage)
      else
        raise Exceptions::StageNotFound.new(
          "Cannot remove stage with name #{stage_name}, stage does not exist."
        )
      end
    end


    def before(*stage_path, &block)
      stage_name = stage_path.shift
      stages.find { |stage| stage.name == stage_name }.before(*stage_path, &block)
    end

    def after(*stage_path, &block)
      stage_name = stage_path.shift
      stages.find { |stage| stage.name == stage_name }.after(*stage_path, &block)
    end

    def use(plugin,**options, &block)
      if plugin.ancestors.include?(PluginConcern)
        plugin.setup!
        plugin = plugin::Plugin
      end

      instance = if plugin.ancestors.include?(Singleton)
        plugin.instance
      elsif plugin.kind_of?(Class)
        plugin.new
      else
        plugin
      end

      instance.application = application
      instance.options.merge!(options)
      instance.block = block if block_given?

      if application.plugins.key?(instance.config_key)
        raise "Can not use plugin: #{plugin}, another plugin is already registered with key: #{instance.config_key}"
      end

      if instance.config_key.nil?
        raise "Error initializing plugin: #{plugin}, config_key may not be nil."
      end

      application.plugins[instance.config_key] = instance
      instance
    end

    def setup!
      # use the Stats and Notifications plugins by default
      use Praxis::Stats
      use Praxis::Notifications

      run
    end

    def run
      stages.each do |stage|
        stage.setup!
        stage.run
      end
    end

  end


end
