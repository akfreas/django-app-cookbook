#
# Cookbook Name:: django-app
# Recipe:: default
#
# Copyright 2013, Sashimiblade
#
# All rights reserved - Do Not Redistribute
#
#

include_recipe "postgresql::server"
include_recipe "supervisor"
include_recipe "database::postgresql"
include_recipe "python"

data_bag = data_bag_item('apps', node['deploy']['data_bag'])

app_home = "#{node['deploy']['deploy_to']}/current"
app_root = "#{app_home}/#{node['deploy']['app_name']}"

applet_name = node['deploy']['applet_name']

template "/etc/nginx/sites-available/default" do
    source "nginx-default.erb"
    owner "root"
    group "root"
    variables(
        :app_home => app_home,
        :app_root => app_root,
        :staticfiles_root => node['deploy']['staticfiles_root'],
        :domain => node['deploy']['domain']
    )
end

supervisor_service node['deploy']['domain'] do
    action :enable
    autostart true
    autorestart true
    command "#{app_home}/bin/gunicorn #{node['deploy']['app_name']}.wsgi:application -b unix:/tmp/gunicorn_#{node['deploy']['domain']}.sock --pythonpath #{app_home} --workers=2 --timeout=10"
    user node['deploy']['user']
end

template "#{app_root}/#{applet_name}/local_settings.py" do
    source "local_settings.py.erb"
    owner node['deploy']['user']
    group node['deploy']['group']
    variables(
        :database_name => node['deploy']['postgresql']['database_name'],
        :user => node['deploy']['postgresql']['user'],
        :password => data_bag['postgresql']['password']
    )
    action :nothing
end

directory "/home/#{node['deploy']['user']}/.ssh" do
    not_if {File.exists?("/home/#{node['deploy']['user']}/.ssh")}
    owner node['deploy']['user']
    group node['deploy']['group']
    mode 0755
    action :create
end

file "/home/#{node['deploy']['user']}/.ssh/id_deploy" do
    only_if{ defined? data_bag['rsa_key'] }
    user node['deploy']['user']
    mode 0600
    content data_bag['rsa_key']
end

file "/home/#{node['deploy']['user']}/ssh_git_wrapper.sh" do
    mode 0755
    content <<-EOT
    #!/bin/sh
    /usr/bin/env ssh  -o "StrictHostKeyChecking=no" -i "/home/#{node['deploy']['user']}/.ssh/id_deploy" $1 $2
    EOT
end

execute "create-database" do
    not_if "sudo -u postgres psql -l -U postgres | grep #{node['deploy']['postgresql']['database_name']}"
    action :run
    command "sudo -u postgres createdb -U postgres -O postgres #{node['deploy']['postgresql']['database_name']}"
    notifies :run, "execute[create_db_user]"
end

execute "create_db_user" do
    action :nothing
    command "echo \"CREATE USER #{node['deploy']['postgresql']['user']} WITH PASSWORD '#{data_bag['postgresql']['password']}';\" | sudo -u postgres psql"
    notifies :run, "execute[configure_db_user]"
end 

execute "configure_db_user" do
    action :nothing
    command "echo \"GRANT ALL PRIVILEGES ON DATABASE #{node['deploy']['postgresql']['database_name']} to #{node['deploy']['postgresql']['user']};\" | sudo -u postgres psql"
end

execute "migrate_db" do 
    command "#{app_home}/bin/python #{app_root}/manage.py syncdb; #{app_home}/bin/python #{app_root}/manage.py migrate"
    action :nothing
end

def install_fixtures
    fixture_path = "#{app_home}/#{app_root}/#{applet_name}/fixtures/initial"
    fixture_list = Array.new
    if Dir.exists? fixture_path
        Dir.foreach(fixture_path) do |fixture| 
            puts "XXXX #{fixture}"
            if fixture != "." && fixture != ".."
                fixture_list.push(fixture)
            end
        end
    end
    command "#{app_home}/bin/python #{app_root}/manage.py loaddata #{fixture_list.join(" ")}" 
end

execute "restart_supervisord" do
    command "sudo killall supervisord; sleep 2; supervisord;"
end
  
deploy node['deploy']['deploy_to'] do 
    repo node['deploy']['repository']
    revision node['deploy']['branch']
    user node['deploy']['user']
    symlinks {}
    symlink_before_migrate({})
    ssh_wrapper "/home/#{node['deploy']['user']}/ssh_git_wrapper.sh"
    action :force_deploy
    migrate false
    migration_command "#{release_path}/bin/python #{release_path}/#{app_name}/manage.py syncdb && #{release_path}/bin/python #{release_path}/#{app_name}/manage.py migrate"
    before_migrate do

        Chef::Log.debug("Hitting before_restart block.")
        Chef::Resource::Notification.new("template[#{app_root}/#{applet_name}/local_settings.py", :create)
        execute "activate_virtualenv" do
            cwd release_path
            command "virtualenv ."
        end
 
        python_pip "#{release_path}/requirements.pip" do
            virtualenv release_path
            options "-r"
            action :install
        end

        execute "move_facebook" do #HAX for the stupid way facebook puts their script directly into site-packages
            cwd release_path
            only_if {File.exists?("#{release_path}/lib/python2.7/site-packages/facebook.py")}
            command "mv lib/python2.7/site-packages/facebook.py lib/python2.7/site-packages/facebook/"
        end
    end
    Chef::Log.debug("Hitting notifiction commmands.")
    notifies :create, "template[#{app_root}/#{applet_name}/local_settings.py]"
    notifies :run, "execute[migrate_db]"
    notifies :run, "execute[restart_supervisord]"
end

