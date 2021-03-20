process.env.NODE_ENV = process.env.NODE_ENV || 'production'

const environment = require('./environment')

const SentryCliPlugin = require("@sentry/webpack-plugin")

environment.config.merge({ devtool: "source-map" })
environment.plugins.prepend(
  "Sentry",
  new SentryCliPlugin({
    include: "./public/",
    ignore: ["node_modules"],
    authToken: process.env.SENTRY_AUTH_TOKEN,
    org: "sentry-sdks",
    project: "sentry-ruby",    
    stripPrefix: ["public"],
  })
)

module.exports = environment.toWebpackConfig()

