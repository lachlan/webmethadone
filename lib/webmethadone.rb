require 'rubygems'
require 'net/https'
require 'optparse'
require 'cgi'

module WebMethadone
  class IntegrationServer
    def initialize(url, service, user, password, timeout)
      @url, @service, @user, @password, @timeout = URI.parse(url.to_s), service, user, password, timeout
    end
    
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
    
    def stop(*args)
      unless stopped?
        get '/invoke/wm.server.admin/shutdown?bounce=no&timeout=0&option=force'
        wait_until("Stopping") do
          stopped?
        end
      end
    end
    
    def restart(*args)
      stop
      start
    end
    
    def ping(*args)
      get '/invoke/wm.server/ping'
    end
    
    def install(package)
      wait_until("Installing package") do
        get "/invoke/wm.server.packages/packageInstall?activateOnInstall=true&file=#{CGI.escape package.to_s}"
      end
    end
    
    def delete(package)
      wait_until("Deleting package") do
        get "/invoke/wm.server.packages/packageDelete?package=#{CGI.escape package.to_s}"
      end
    end
    
    def disable(package)
      wait_until("Disabling package") do
        get "/invoke/wm.server.packages/packageDisable?package=#{CGI.escape package.to_s}"
      end
    end
    
    def enable(package)
      wait_until("Enabling package") do
        get "/invoke/wm.server.packages/packageEnable?package=#{CGI.escape package.to_s}"
      end
    end
    
    def reload(package)
      wait_until("Reloading package") do
        get "/invoke/wm.server.packages/packageReload?package=#{CGI.escape package.to_s}"
      end
    end
    
    def started?
      begin
        ping
        return true
      rescue => ex
        return false
      end
    end
    
    def stopped?
      cmd = "cmd.exe /c \"sc"
      cmd += " \\#{@url.host}" unless @url.host == 'localhost'
      cmd += " query #{@service} | findstr /i /c:\"STATE\" | findstr /i /c:\"STOPPED\" > NUL 2>&1\""
      
      system cmd
      return $?.to_i == 0
    end  
    
    private
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
    
    def wait_until(msg = nil)
      msg_thread, work_thread = nil, nil
      
      if msg
        print "#{msg}"
        $stdout.flush      
        msg_thread = Thread.new do
          while true
            print "."
            $stdout.flush
            sleep 1
          end
        end
      end
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