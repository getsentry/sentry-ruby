# frozen_string_literal: true

require "sequel"
require "sentry/sequel"

class SequelUsersController < ActionController::Base
  def index
    users = SEQUEL_DB[:users].all
    render json: users
  end

  def create
    id = SEQUEL_DB[:users].insert(name: params[:name], email: params[:email])
    render json: { id: id, name: params[:name], email: params[:email] }, status: :created
  end

  def show
    user = SEQUEL_DB[:users].where(id: params[:id]).first
    if user
      render json: user
    else
      render json: { error: "Not found" }, status: :not_found
    end
  end

  def update
    SEQUEL_DB[:users].where(id: params[:id]).update(name: params[:name])
    user = SEQUEL_DB[:users].where(id: params[:id]).first
    render json: user
  end

  def destroy
    SEQUEL_DB[:users].where(id: params[:id]).delete
    head :no_content
  end

  def exception
    SEQUEL_DB[:users].all
    raise "Something went wrong!"
  end
end
