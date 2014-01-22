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

app_config = data_bag_item('apps', node['deploy']['data_bag'])

app_home = "#{app_config['deploy_to']}/current"
app_root = "#{app_home}/#{app_config['app_name']}"

applet_name = app_config['applet_name']

execute "migrate_db" do 
    command "#{app_home}/bin/python #{app_root}/manage.py syncdb; #{app_home}/bin/python #{app_root}/manage.py migrate"
    action :nothing
end

execute "restart_supervisord" do
    command "sudo killall supervisord; sleep 2; supervisord;"
    action :nothing
end
  
deploy app_config['deploy_to'] do 
    repo app_config['repository']
    revision app_config['branch']
    user app_config['user']
    symlinks {}
    symlink_before_migrate({})
    ssh_wrapper "/home/#{app_config['user']}/ssh_git_wrapper.sh"
    action :deploy
    migrate false
    notifies :run, "execute[migrate_db]"
    notifies :run, "execute[restart_supervisord]"
end
