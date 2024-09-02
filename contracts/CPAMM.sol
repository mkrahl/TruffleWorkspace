// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SD59x18, sd } from "@prb/math/src/SD59x18.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";

contract CPAMM {
    IERC20 public immutable token0; // MoneyToken address
    IERC20 public immutable token1; // EnergyToken address

    int256 public reserve0 = 0; // MoneyTokens in LP
    int256 public reserve1 = 0; // EnergyTokens in LP

    SD59x18 public immutable k_lower; // lower price limit
    SD59x18 public immutable k_upper; // upper price limit
    SD59x18 public immutable midpoint; // parameter for sigmoid bonding curve
    SD59x18 public immutable steepness; // parameter for sigmoid bonding curve

    int256 constant uEXP_MAX_INPUT = 133_084258667509499440; // Max input for exp function used in pricing to avoid overflow
    SD59x18 constant EXP_MAX_INPUT = SD59x18.wrap(uEXP_MAX_INPUT);

    /* struct to store energy and money balances of members*/
    struct balance_Struct {
        uint256 token0_balance; 
        uint256 token1_balance;
    }  

    /* List of Market Participants that have submitted trades. Gets reset after each market clearing. 
    Note: Acts as the keys for balanceOf mapping*/
    address[] public current_member_list;

    /* How many market participants are in the market. When all those members have submitted their trades, the market is cleard. 
    In a realistic setting, this would happen in fixed time intervals*/
    uint256 public immutable total_member_count;

    //  Mapping to keep track of deposited tokens during swapping phase. Gets reset after each market clearing
    mapping(address => balance_Struct) public balanceOf;

    constructor(address _token0, address _token1,uint256 _members,uint256 _k_lower,uint256 _k_upper,uint256 _midpoint,uint256 _steepness) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        total_member_count = _members;
        k_lower = sd(int256(_k_lower * 1e16));
        k_upper = sd(int256(_k_upper * 1e16));
        midpoint = sd(int256(_midpoint* 1e18));
        steepness = sd(int256(_steepness*1e18));
    }
    
    function swap(address _tokenIn, uint256 _amountIn) external{

        // check for correct token to be swapped
        require(_tokenIn == address(token0) || _tokenIn == address(token1),"invalid token");

        //check if sender already submitted. Ensures only one token is swapped for each market clearing window.
        require(_exists(msg.sender),"Account already deposited");

        // determine which token is deposited
        bool isToken0 = _tokenIn == address(token0);

        // transfer the token to contract. Needs prior allowance from user.
        IERC20 tokenIn = IERC20(_tokenIn);
        tokenIn.transferFrom(msg.sender, address(this), _amountIn);

        // update reserve
        _update(int256(token0.balanceOf(address(this))), int256(token1.balanceOf(address(this))));

        // increase member count
        current_member_list.push(msg.sender);

        // update sender balance
        isToken0 ? balanceOf[msg.sender].token0_balance = _amountIn : balanceOf[msg.sender].token1_balance = _amountIn;

        //check if all members have distributed, if so, clear market
        if (current_member_list.length == total_member_count){
            _clear();
        }
    }
    
    function _clear() private {

        SD59x18 price_per_energy = _get_price(reserve0, reserve1);

        for (uint256 i = 0; i < current_member_list.length; i++ ){
            address member = current_member_list[i];
            int256 token0_balance = int256(balanceOf[member].token0_balance);
            int256 token1_balance = int256(balanceOf[member].token1_balance);
            // if member deposited energy
            if (token1_balance > 0){
                uint256 amount_out = uint256(price_per_energy.mul(sd(token1_balance)).intoInt256());
                token0.transfer(member,amount_out);
            }
            // if memeber deposited money
            else {
                uint256 amount_out = uint256(sd(reserve1).mul(sd(reserve0).div(sd(token0_balance))).intoInt256());
                token1.transfer(member,amount_out);
                uint256 price = uint256(sd(int256(amount_out)).mul(price_per_energy).intoInt256());
                token0.transfer(member,uint256(token0_balance)-price);
            }


        }
        

    }

    function test(int256 _reserve0,int256 _reserve1) public pure returns (int256){
        return (sd(2e18) * sd(1e18)).intoInt256();
    }

    function _get_price(int256 _reserve0, int256 _reserve1) public view returns (SD59x18){
        SD59x18 ratio = sd(_reserve1).div(sd(_reserve0));
        SD59x18 nominator = k_upper.sub(k_lower);
        if(ratio.sub(midpoint) <= EXP_MAX_INPUT){

            SD59x18 pow = steepness.mul(ratio.sub(midpoint));
            SD59x18 denominator = sd(1e18).add(pow.exp());

            SD59x18 result = k_upper.sub(nominator.div(denominator));

            return result;
        }
        else {
            return k_upper;
        }
    }

    function _sqrt(uint256 y) private pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _min(uint256 x, uint256 y) private pure returns (uint256) {
        return x <= y ? x : y;
    }

    function _update(int256 _res0, int256 _res1) private {
        reserve0 = _res0;
        reserve1 = _res1;
    }
    function _exists (address member) private view returns (bool){
        for(uint256 i=0;i < current_member_list.length;i++){
            if (current_member_list[i] == member){
                return true;
            }
        }
        return false;
    }
}