class WelcomeController < ApplicationController
  def index
    1 / 0
  end

  def report_demo
    render(status: 500)
  end
end
