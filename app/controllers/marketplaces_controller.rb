##
## Copyright [2013-2015] [Megam Systems]
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
## http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
##
require 'json'

class MarketplacesController < ApplicationController
  respond_to :js
  include MarketplaceHelper

  before_action :stick_keys, only: [:index, :show, :create]
  ##
  ## index page get all marketplace items from storage(we use riak) using megam_gateway
  ## and show the items in order of category
  ##
  def index
    logger.debug '> Marketplaces: index.'
    @mkp_grouped = Marketplaces.instance.list(params).mkp_grouped
  end

  ##
  ## to show the selected marketplace catalog item, appears if there are credits in billing.
  ##
  def show
    logger.debug '> Marketplaces: show.'
    Balances.new.show(params) do  |modb|
      unless modb.balance.credit.to_i > 0
        respond_to do |format|
          format.html { redirect_to billings_path }
          format.js { render js: "window.location.href='" + billings_path + "'" }
        end
      else
        @mkp = pressurize_version(Marketplaces.instance.show(params).mkp, params['version'])
        @ssh_keys = Sshkeys.new.list(params).ssh_keys
        @unbound_apps = unbound_apps(Assemblies.new.list(params.merge(flying_apps: 'true')).apps) if @mkp['cattype'] == Assemblies::SERVICE
        respond_to do |format|
          format.js do
            respond_with(@mkp, @ssh_keys, @unbound_apps, layout: !request.xhr?)
          end
        end
      end
    end
  end

  ## super cool - omni creator for all.
  # performs ssh creation or using existing and creating an assembly at the end.
  def create
    logger.debug '> Marketplaces: create.'
    puts '========================================================='
    puts params[:source]
    mkp = JSON.parse(params[:mkp])
    params[:ssh_keypair_name] = params["#{params[:sshoption]}" + '_name'] if params[:sshoption] == Sshkeys::USEOLD
    params[:ssh_keypair_name] = params["#{Sshkeys::NEW}_name"] unless params[:sshoption] == Sshkeys::USEOLD
    Sshkeys.new.create_or_import(params)
    setup_scm(params)
    res = Assemblies.new.create(params)
    binded_app?(params) do
      Assembly.new.update(params)
      Components.new.update(params)
    end if params.key?(:bindedAPP)
    @msg = { title: "#{mkp['cattype']}".downcase.camelize, message: "#{params['assemblyname']}.#{params['domain']} launched successfully. ", redirect: '/', disposal_id: 'app-1' }
  end

  ##
  ## after finish the github authentication the callback url comes this method
  ## this function parse the request and get the github credentials
  ## and store that credentials to session
  ##
  def store_github
    @auth_token = request.env['omniauth.auth']['credentials']['token']
    session[:github] =  @auth_token
    session[:git_owner] = request.env['omniauth.auth']['extra']['raw_info']['login']
  end

  ##
  ## this method collect all repositories for user using oauth token
  ##
  def publish_github
    auth_id = params['id']
    github = Github.new oauth_token: session[:github]
    git_array = github.repos.all.collect(&:clone_url)
    @repos = git_array
    respond_to do |format|
      format.js do
        respond_with(@repos, layout: !request.xhr?)
      end
    end
  end

  ##
  ## gogswindow html page method
  ##
  def start_gogs
  end

  ##
  ## get the repositories from session
  ## SCRP: What happens if gogs fails.
  def publish_gogs
    @repos = session[:gogs_repos]
    respond_to do |format|
      format.js do
        respond_with(@repos, layout: !request.xhr?)
      end
    end
  end

  ##
  ## this function get the gogs token using username and password
  ## then list the repositories using oauth tokens.
  ## SCRP: There is no error trap here. What happens if gogs fails ?
  def store_gogs
    session[:gogs_owner] = params[:gogs_username]
    tokens = ListGogsTokens.perform(params[:gogs_username], params[:gogs_password])
    session[:gogs_token] = JSON.parse(tokens)[0]['sha1']
    @gogs_repos = ListGogsRepo.perform(token)
    obj_repo = JSON.parse(@gogs_repos)
    @repos_arr = []
    obj_repo.each do |one_repo|
      @repos_arr << one_repo['clone_url']
    end
    session[:gogs_repos] =  @repos_arr
  end

  private

  def binded_app?(params, &_block)
    yield if block_given? unless params[:bindedAPP].eql?('Unbound service')
  end

  def setup_scm(params)
    case params[:scm_name]
    when Scm::GITHUB
      params[:scmtoken] =  session[:github]
      params[:scmowner] =  session[:git_owner]
    when Scm::GOGS
      params[:scmtoken] =  session[:gogs_token]
      params[:scmowner] =  session[:gogs_owner]
    else
      # we ignore it.
    end
  end
end
