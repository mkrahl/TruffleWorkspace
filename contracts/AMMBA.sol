// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SD59x18, sd } from "@prb/math/src/SD59x18.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";

contract AMMBA {
    event RefundEvent(uint256 refund_to, uint256 amount,uint256 balance );
    event EnergyEvent(uint256 refund_to, uint256 amount,uint256 balance );
    IERC20 public immutable token0; // MoneyToken address
    IERC20 public immutable token1; // EnergyToken address

    uint256 public reserve0 = 0; // MoneyTokens in LP
    uint256 public reserve1 = 0; // EnergyTokens in LP

    SD59x18 public k_lower; // lower price limit
    SD59x18 public k_upper; // upper price limit
    SD59x18 public midpoint; // parameter for sigmoid bonding curve
    SD59x18 public steepness; // parameter for sigmoid bonding curve

    int256 constant uEXP_MAX_INPUT = 133_084258667509499440; // Max input for exp function used in pricing to avoid overflow
    SD59x18 constant EXP_MAX_INPUT = SD59x18.wrap(uEXP_MAX_INPUT);

    /* struct to store energy and money balances of members*/
    struct balance_Struct {
        uint256 token0_balance; 
        uint256 token1_balance;
        bool has_deposited;
        uint256 token0_out;
        uint256 token1_out;
    }  

    /* List of Market Participants that have submitted trades. Gets reset after each market clearing. 
    Note: Acts as the keys for balanceOf mapping*/
    address[] public current_member_list;

    /* How many market participants are in the market. When all those members have submitted their trades, the market is cleard. 
    In a realistic setting, this would happen in fixed time intervals*/
    uint256 public immutable total_member_count;

    //  Mapping to keep track of deposited tokens during swapping phase. Gets reset after each market clearing
    uint256 public current_mapping_count = 0;
    mapping(uint256 => mapping(address => balance_Struct)) public balanceOf;

    // Mapping to keep track of price per energy for every round.
    mapping(uint256 => uint256) public prices;

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
        require(!(_exists(msg.sender)),"Account already deposited");

        // determine which token is deposited
        bool isToken0 = _tokenIn == address(token0);

        // transfer the token to contract. Needs prior allowance from user.
        IERC20 tokenIn = IERC20(_tokenIn);
        tokenIn.transferFrom(msg.sender, address(this), _amountIn);

        // update reserve
        _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)));

        // increase member count
        current_member_list.push(msg.sender);

        // update sender balance
        isToken0 ? balanceOf[current_mapping_count][msg.sender].token0_balance = _amountIn : balanceOf[current_mapping_count][msg.sender].token1_balance = _amountIn;

        //set inidactor that account has deposited
        balanceOf[current_mapping_count][msg.sender].has_deposited = true;
    }
    
    function clear() external {
        SD59x18 price_per_energy = get_price(reserve0,reserve1);
        prices[current_mapping_count] = uint256(price_per_energy.intoInt256());
        for (uint256 i = 0; i < current_member_list.length; i++ ){
            address member = current_member_list[i];
            uint256 token0_balance = balanceOf[current_mapping_count][member].token0_balance;
            uint256 token1_balance = balanceOf[current_mapping_count][member].token1_balance;
            int256 total_demand = sd(int256(reserve0)).div(price_per_energy).intoInt256(); 
            // if member deposited energy
            if (token1_balance > 0){
                uint256 amount_out = uint256(price_per_energy.mul(sd(int256(token1_balance))).intoInt256());
                balanceOf[current_mapping_count][member].token0_out = amount_out;
                // if energy surpuls, transfer part of energy tokens back to sender
                if (int256(reserve1) > total_demand){
                    uint256 surplus = uint256(sd(int256(reserve1)).sub(sd(total_demand)).mul(sd(int256(token1_balance)).div(sd(int256(reserve1)))).intoInt256());
                    balanceOf[current_mapping_count][member].token1_out = surplus;
                }
            }
            // if memeber deposited money
            else {
                uint256 amount_out = uint256(sd(int256(reserve1)).mul(sd(int256(token0_balance)).div(sd(int256(reserve0)))).intoInt256());
                balanceOf[current_mapping_count][member].token1_out = amount_out;
                uint256 price = uint256(sd(int256(amount_out)).mul(price_per_energy).intoInt256());
                balanceOf[current_mapping_count][member].token0_out = token0_balance - price;
            }


        }
        
        for (uint256 i = 0; i < current_member_list.length; i++){
            address member = current_member_list[i];
            uint256 token0_out = balanceOf[current_mapping_count][member].token0_out;
            uint256 token1_out = balanceOf[current_mapping_count][member].token1_out;
            if (token0_out > 100){
                token0.transfer(member,token0_out-100);
            }
            if (token1_out > 100){
                token1.transfer(member,token1_out-100);
            }
        } 
        
        current_mapping_count= current_mapping_count+1;
        delete current_member_list;
    }

    function get_price(uint256 _reserve0,uint256 _reserve1) public view returns (SD59x18){
        SD59x18 ratio = sd(int256(_reserve1)).div(sd(int256(_reserve0)));
        SD59x18 nominator = k_upper.sub(k_lower);
        if(ratio.sub(midpoint) <= EXP_MAX_INPUT){

            SD59x18 pow = sd(0).sub(steepness).mul(ratio.sub(midpoint));
            SD59x18 denominator = sd(1e18).add(pow.exp());

            SD59x18 result = k_upper.sub(nominator.div(denominator));

            return result;
        }
        else {
            return k_upper;
        }
    }

    function _update(uint256 _res0, uint256 _res1) private {
        reserve0 = _res0;
        reserve1 = _res1;
    }
    function _exists (address member) private view returns (bool){
        return balanceOf[current_mapping_count][member].has_deposited;
    }
    function get_reserve0() public view returns (uint256){
        return uint256(reserve0);
    }
    function get_reserve1() public view returns (uint256){
        return uint256(reserve1);
    }
    function set_k_lower(uint256 _k_lower) public {
        k_lower = sd(int256(_k_lower));
    }
    function set_k_upper(uint256 _k_upper) public {
        k_upper = sd(int256(_k_upper));
    }
    function set_steepness(uint256 _steepness) public {
        steepness=sd(int256(_steepness));
    }
    function set_midpoint(uint256 _midpoint) public {
        midpoint = sd(int256(_midpoint));
    }

    function get_member_info(uint256 round, address member) public view returns(uint256,uint256,bool,uint256,uint256){
        return ( balanceOf[round][member].token0_balance,balanceOf[round][member].token1_balance,balanceOf[round][member].has_deposited,balanceOf[round][member].token0_out,balanceOf[round][member].token1_out);
    }
    function get_price(uint256 round) public view returns(uint256){
        return prices[round];
    }
}