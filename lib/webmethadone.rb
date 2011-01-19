require 'rubygems'
require 'net/https'
require 'optparse'
require 'cgi'

module WebMethadone
  # Ruby client for a webMethods Integration Server (IS) instance.  Lets you start, stop, restart and ping the server, 
  # and lets you install, enable, reload, disable, and delete packages.
  class IntegrationServer
    # Creates a new Integration Server client.
    #
    # url      - The Integration Server to connect to.
    # service  - The Integration Server windows service name, required for starting IS.
    # user     - The user to use when connecting to the server.
    # password - The password to use when connecting to the server.
    # timeout  - The number of seconds to wait for an HTTP response from the server.
    #
    # Examples
    #
    #   IntegrationServer.new('http://localhost:5555', 'webMethodsIntegrationServer_7.1', 'Administrator', 'manage', 600)
    #
    def initialize(url, service, user, password, timeout)
      @url, @service, @user, @password, @timeout = URI.parse(url.to_s), service, user, password, timeout
    end
    
    # Starts webMethods Integration Server by issuing a system 'sc start' to the Windows service.
    def start(*args)
      unless started?
        # Windows only: start the webMethods windows service
        # TODO: how to start webMethods on other platforms?
        # TODO: how to start webMethods as a batch file?
        cmd = "sc"
        cmd += " \\#{@url.host}" unless @url.host == 'localhost'
        cmd += " start #{@service} > NUL 2>&1"
        system cmd

        wait_until("Starting") do 
          started?
        end
      end
    end
    
    # Stops webMethods Integration Server via an HTTP invoke of shutdown service.
    def stop(*args)
      unless stopped?
        get '/invoke/wm.server.admin/shutdown?bounce=no&timeout=0&option=force'
        wait_until("Stopping") do
          stopped?
        end
      end
    end
    
    # Restarts webMethods Integration Server by stopping and starting it.
    def restart(*args)
      stop
      start
    end
    
    # Pings webMethods Integration Server via an HTTP invoke of ping service.
    def ping(*args)
      get '/invoke/wm.server/ping'
    end
    
    # Installs a package in Integration Server.  Package zip archive must already be
    # in ./replicate/inbound directory.
    def install(package)
      wait_until("Installing package") do
        get "/invoke/wm.server.packages/packageInstall?activateOnInstall=true&file=#{CGI.escape package.to_s}"
      end
    end
    
    # Deletes a package from Integration Server.
    def delete(package)
      wait_until("Deleting package") do
        get "/invoke/wm.server.packages/packageDelete?package=#{CGI.escape package.to_s}"
      end
    end
    
    # Disables a package in Integration Server.
    def disable(package)
      wait_until("Disabling package") do
        get "/invoke/wm.server.packages/packageDisable?package=#{CGI.escape package.to_s}"
      end
    end
    
    # Enables a package in Integration Server.
    def enable(package)
      wait_until("Enabling package") do
        get "/invoke/wm.server.packages/packageEnable?package=#{CGI.escape package.to_s}"
      end
    end
    
    # Reloads a package in Integration Server.
    def reload(package)
      wait_until("Reloading package") do
        get "/invoke/wm.server.packages/packageReload?package=#{CGI.escape package.to_s}"
      end
    end
    
    # Is this Integration Server currently started?
    def started?
      begin
        ping
        return true
      rescue => ex
        return false
      end
    end
    
    # Is this Integration Server currently stopped?
    def stopped?
      cmd = "cmd.exe /c \"sc"
      cmd += " \\#{@url.host}" unless @url.host == 'localhost'
      cmd += " query #{@service} | findstr /i /c:\"STATE\" | findstr /i /c:\"STOPPED\" > NUL 2>&1\""
      
      system cmd
      return $?.to_i == 0
    end  
    
    private
    # HTTP GETs the given path against this Integration Server
    def get(path = nil)
      url = URI.parse(@url.scheme + '://' + @url.host + ':' + @url.port.to_s + path.to_s)
      headers = { "Authorization" => "Basic " + [@user + ":" + @password].pack("m") } if @user
      
      server = Net::HTTP.new(@url.host, @url.port)
      server.read_timeout = @timeout
      server.use_ssl = url.scheme == 'https'
      server.verify_mode = OpenSSL::SSL::VERIFY_NONE
      
      res, data = server.get(url.request_uri, headers)
      
      case res
        when Net::HTTPSuccess
          # OK
        else
          raise res.inspect
      end
      [res, data]
    end
    
    # Retries the given block until it first succeeds, while optionally printing an incremental message to $stdout
    def wait_until(msg = nil)
      if block_given?
        msg_thread, work_thread = nil, nil
      
        # prints incremental '...' message while waiting for the given block to finish successfully
        if msg
          print "#{msg.to_s}..."
          msg_thread = Thread.new do
            loop do
              print "."
              $stdout.flush
              sleep 1
            end
          end
        end
        
        # repeatedly yields to the given block until it returns true
        work_thread = Thread.new do
          result = false
          until result
            result = yield
            sleep 1
          end
        end
        
        work_thread.join if work_thread
        msg_thread.kill if msg_thread
        
        print "\n" if msg
      end
    end
  end
end