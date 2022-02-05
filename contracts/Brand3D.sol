// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/token/ERC777/ERC777.sol";

contract Brand3D is ERC777 {
  uint256 EXCHANGE_RATE = 3300;

  constructor(uint256 initialSupply, address[] memory defaultOperators)
    ERC777("Brand3D", "BRANDY", defaultOperators)
  {
    _mint(msg.sender, initialSupply * 10**18, "", "");
  }

  // to be replaced with uniswap LP in the future
  function swap() external payable {
    _mint(msg.sender, msg.value * EXCHANGE_RATE, "", "");
  }
}
