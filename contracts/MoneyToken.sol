pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract MoneyToken is ERC20{
    address payable public owner;
    constructor() ERC20("MoneyToken","MOT") {
        owner = payable(msg.sender);
        _mint(owner, 7000000 * (10 ** decimals()));
    }
    modifier onlyOwner {
        require(msg.sender == owner,"Only the owner can call this function");
        _;
    }
}