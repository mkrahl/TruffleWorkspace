const MyToken = artifacts.require("Test");

module.exports = (deployer) => {
    deployer.deploy(MyToken);
};