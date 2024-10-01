const MyToken = artifacts.require("AMMBA");

module.exports = (deployer) => {
    deployer.deploy(MyToken,"0xe78A0F7E598Cc8b0Bb87894B0F60dD2a88d6a8Ab","0x5b1869D9A4C187F2EAa108f3062412ecf0526b24",250,8,34,0,1);
};