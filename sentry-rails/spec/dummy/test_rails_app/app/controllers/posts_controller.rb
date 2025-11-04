# frozen_string_literal: true

class PostsController < ActionController::Base
  def index
    Post.all.to_a
    raise "foo"
  end

  def show
    p = Post.find(params[:id])

    render plain: p.id
  end

  def attach
    p = Post.find(params[:id])

    attach_params = {
      io: File.open(File.join(Rails.root, "public", "sentry-logo.png")),
      filename: "sentry-logo.png"
    }

    # service_name parameter was added in Rails 6.1
    if Rails.gem_version >= Gem::Version.new("6.1.0")
      attach_params[:service_name] = "test"
    end

    p.cover.attach(attach_params)

    render plain: p.id
  end
end
