// Load `*.js` under current directory as one object
const path = require('path')
const fs = require('fs')
let packages = {}

fs.readdirSync(path.resolve(__dirname)).forEach(file => {
  if (file.match(/\.js$/) && file !== 'index.js') {
    const name = file.replace('.js', '')
    packages[name] = require(`./${file}`)
  }
})

const {tap, ...rest} = packages
packages = {tap, ...rest}

module.exports = packages
