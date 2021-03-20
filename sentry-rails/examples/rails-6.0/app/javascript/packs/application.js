// This file is automatically compiled by Webpack, along with any other files
// present in this directory. You're encouraged to place your actual application logic in
// a relevant structure within app/javascript and only use these pack files to reference
// that code so it'll be compiled.

import { init, captureMessage } from '@sentry/browser';

init({
  dsn: 'https://2fb45f003d054a7ea47feb45898f7649@o447951.ingest.sentry.io/5434472',
});

captureMessage("hello");
console.log("Foo");


// Uncomment to copy all static images under ../images to the output folder and reference
// them with the image_pack_tag helper in views (e.g <%= image_pack_tag 'rails.png' %>)
// or the `imagePath` JavaScript helper below.
//
// const images = require.context('../images', true)
// const imagePath = (name) => images(name, true)
