pragma solidity ^0.4.0;

contract Mortal {
  function kill(address _refundAccount) internal{
    suicide(_refundAccount);
  }
}
