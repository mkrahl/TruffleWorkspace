pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract Test{
    ERC20 public immutable token0 =ERC20(0xe78A0F7E598Cc8b0Bb87894B0F60dD2a88d6a8Ab);
    uint256 public counter = 0;
    constructor() {
        counter = 1;
    }
    function add() public {
        counter = counter +1;
    }
    function send(uint256 amount) public {
        token0.transferFrom(msg.sender, address(this), amount);
    }
}