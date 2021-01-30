import consumer from './consumer';

consumer.subscriptions.create('AppearanceChannel', {
  initialized() {
    this.hello = this.hello.bind(this);
    this.goodbye = this.goodbye.bind(this);
  },

  connected() {
    document.querySelector('button#hello').addEventListener('click', this.hello);
    document.querySelector('button#goodbye').addEventListener('click', this.goodbye);
  },

  disconnect() {
    document.querySelector('button#hello').removeEventListener('click', this.hello);
    document.querySelector('button#goodbye').removeEventListener('click', this.goodbye);
  },

  hello() {
    this.perform('hello');
  },

  goodbye() {
    this.perform('goodbye', { forever: true });
  }
});
