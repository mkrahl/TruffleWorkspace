const MyToken = artifacts.require("EnergyToken");

module.exports = (deployer) => {
    deployer.deploy(MyToken);
};