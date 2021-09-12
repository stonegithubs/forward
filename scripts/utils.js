const fs = require('fs')


function getConfig() {
    return JSON.parse(
        fs.readFileSync(`${process.cwd()}/config/config.json`).toString()
    )
}

function writeConfig(contractAddresses) {
    fs.writeFileSync(
        `${process.cwd()}/config/config.json`,
        JSON.stringify(contractAddresses, null, 4) // Indent 4 spaces
    )
}

module.exports = {
    getConfig,
    writeConfig
}
