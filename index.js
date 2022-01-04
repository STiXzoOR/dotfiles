const emoji = require('node-emoji')
const packages = require('./packages/')
const { exec } = require('promisify-child-process')

const colorize = (color, str) => {
  const palette = {
    none: 0,
    red: 31,
    green: 32,
    yellow: 33,
    cyan: 36,
    white: 37
  }

  return `\x1b[${palette[color]}m${str}\x1b[0m`
}

const command = (type, item) =>
  exec(
    `. scripts/echos.sh && . scripts/requirers.sh && require_${type} ${item}`,
    { cwd: __dirname }
  )

const finished = Object.keys(packages).reduce((prevTypePromise, type) => {
  return prevTypePromise.then(() => {
    if (packages[type].length) {
      console.log(`\n${emoji.get('coffee')} installing ${type} packages\n`)

      return packages[type].reduce((prevItemPromise, item) => {
        return prevItemPromise.then(() => {
          process.stdout.write(` ⇒ ${item} `)

          return command(type, item)
            .then(() => {
              console.info(colorize('green', '✓'))
            })
            .catch(err => {
              console.error(colorize('red', '✗'))
              console.error(`\n  ⇒  ${err}\n`)
            })
        })
      }, Promise.resolve())
    }
  })
}, Promise.resolve())

finished.then(() => {
  console.log(`${emoji.get('rocket')} Package install complete.`)
})
