const MyToken = artifacts.require("MoneyToken");

module.exports = (deployer) => {
    deployer.deploy(MyToken);
};