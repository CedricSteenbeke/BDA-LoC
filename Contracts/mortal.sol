contract Mortal {
  function kill(address _refundAccount) internal{
    suicide(_refundAccount);
  }
}
