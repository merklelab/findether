pragma solidity ^0.4.16;

contract SafeMath {
  function mul(uint128 a, uint128 b) internal constant returns (uint128) {
    uint128 c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function div(uint128 a, uint128 b) internal constant returns (uint128) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    uint128 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return c;
  }

  function sub(uint128 a, uint128 b) internal constant returns (uint128) {
    assert(b <= a);
    return a - b;
  }

  function add(uint128 a, uint128 b) internal constant returns (uint128) {
    uint128 c = a + b;
    assert(c >= a);
    return c;
  }
}



contract FindEther is SafeMath {
  address public owner;
  /* address public arbiter;
  address public relayer; */
  /* uint128 public fee; */
  uint128 public totalFeeForWithdrawal;
  uint8 public INPROGRESS = 1;
  uint8 public PAID = 2;
  uint8 public ESCALATEDBEFOREPAID = 3;
  uint8 public ESCALATEDAFTERPAID = 4;

  event Escrow(address indexed _maker, address indexed _taker, bytes32 key);
  event MarkPaid(address indexed _maker, address indexed _taker, bytes32 key);
  event Cancelled(address indexed _maker, address indexed _taker, bytes32 key);
  event Released(address indexed _maker, address indexed _taker, bytes32 key);
  event Refunded(address indexed _maker, address indexed _taker, bytes32 key);
  event EscrowEscalated(address indexed _maker, address indexed _taker, bytes32 key);
  event EscalationResolved(address indexed _maker, address indexed _taker, bytes32 key);

  struct EscrowStruct
  {
      address maker;          //Person who is making payment
      address taker;         //Person who is sending ether
      address arbiter;
      uint128 amount;            //Amount of Ether (in Wei) buyer will receive after fees
      uint128 findEtherGasFee;
      uint8 status;            //0 for escrowInitiated, 1 for FundReleased to buyer, 2 for FundRefunded to Seller, 3 for EscrowEscalated
      uint128 escrowTime;
  }

  mapping(bytes32 => EscrowStruct) public escrowDatabase;
  mapping(address => bool) public arbiterDatabase;
  mapping(address => bool) public relayerDatabase;

  function FindEther() public{
      owner = msg.sender;
      /* arbiter = msg.sender;
      relayer = msg.sender; */
      /* fee = 1; //Added line// //to be passed in the function
      minimimumTimeBeforeCancel = 7200; */
  }

  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  modifier onlyArbiter() {
    require(arbiterDatabase[msg.sender]);
    _;
  }

  modifier onlyRelayer() {
    require(relayerDatabase[msg.sender]);
    _;
  }

  modifier notInRelayer(address target) {
    require(!relayerDatabase[target]);
    _;
  }

  modifier notInArbiter(address target) {
    require(!arbiterDatabase[target]);
    _;
  }

  modifier inRelayer(address target) {
    require(relayerDatabase[target]);
    _;
  }

  modifier inArbiter(address target) {
    require(arbiterDatabase[target]);
    _;
  }

  function newEscrow(address _takerAddress, address _arbiterAddress, bytes32 _key, uint _value, uint _fee, uint128 _expirationTime, uint128 _escrowTime) payable external returns (bool) {
      require(msg.value > 0);
      require(msg.value == _value);
      require(block.timestamp <= _expirationTime);

      EscrowStruct memory currentEscrow;
      currentEscrow.maker = msg.sender;
      currentEscrow.taker = _takerAddress;
      currentEscrow.arbiter = _arbiterAddress;
      currentEscrow.amount = uint128(msg.value);
      currentEscrow.status = INPROGRESS;
      currentEscrow.findEtherGasFee = 0;
      currentEscrow.escrowTime = uint128(block.timestamp) + _escrowTime;
      escrowDatabase[_key] = currentEscrow;
      Escrow(msg.sender, _takerAddress, _key);
      return true;
  }

  function markPaid(bytes32 _key) private returns(bool){
    require(escrowDatabase[_key].status == INPROGRESS);
    escrowDatabase[_key].status == PAID;
  }

  function cancel(bytes32 _key, uint128 _findEtherGasFee) private returns(bool){
    require(uint128(block.timestamp) >= escrowDatabase[_key].escrowTime);
    require(escrowDatabase[_key].status == INPROGRESS);
    address maker = escrowDatabase[_key].maker;
    uint128 amount = escrowDatabase[_key].amount;
    delete escrowDatabase[_key];
    Cancelled(maker, escrowDatabase[_key].taker, _key);
    transferFunds(maker, amount, 0, _findEtherGasFee);
    return true;
  }

  function release(bytes32 _key, uint128 _findEtherGasFee, uint128 _fee) private returns(bool){
    require(escrowDatabase[_key].status == INPROGRESS || escrowDatabase[_key].status == ESCALATEDBEFOREPAID || escrowDatabase[_key].status == PAID || escrowDatabase[_key].status == ESCALATEDAFTERPAID);
    address taker = escrowDatabase[_key].taker;
    uint128 amount = escrowDatabase[_key].amount;
    delete escrowDatabase[_key];
    Released(escrowDatabase[_key].maker, taker, _key);
    transferFunds(taker, amount, _fee, _findEtherGasFee);
    return true;
  }

    //buyer can refund the seller at any time
  function refund(bytes32 _key, uint128 _findEtherGasFee) private returns(bool){
    require(escrowDatabase[_key].status == INPROGRESS || escrowDatabase[_key].status == ESCALATEDBEFOREPAID || escrowDatabase[_key].status == PAID || escrowDatabase[_key].status == ESCALATEDAFTERPAID);
    address maker = escrowDatabase[_key].maker;
    uint128 amount = escrowDatabase[_key].amount;
    delete escrowDatabase[_key];
    Refunded(maker, escrowDatabase[_key].taker, _key);
    transferFunds(maker, amount, 0, _findEtherGasFee);
    return true;
  }

    //Switcher = 0 for seller, Switcher = 1 for buyer
  function escalation(bytes32 _key) private returns(bool){
   require(escrowDatabase[_key].status == INPROGRESS || escrowDatabase[_key].status == PAID);
   EscrowEscalated(escrowDatabase[_key].maker, escrowDatabase[_key].taker, _key);
   if (escrowDatabase[_key].status == INPROGRESS){
     escrowDatabase[_key].status = ESCALATEDBEFOREPAID;
   }
   else escrowDatabase[_key].status == ESCALATEDAFTERPAID;
   return true;
  }

  function escrowDecision(bytes32 _key, uint128 _buyerPercent, uint128 _fee) external onlyArbiter{
    require(escrowDatabase[_key].status == ESCALATEDBEFOREPAID || escrowDatabase[_key].status == ESCALATEDAFTERPAID);
    escrowDatabase[_key].findEtherGasFee = add(escrowDatabase[_key].findEtherGasFee, mul(47799, uint128(tx.gasprice))); //add something at 0
    uint128 amount = escrowDatabase[_key].amount;
    address taker = escrowDatabase[_key].taker;
    address maker = escrowDatabase[_key].maker;
    uint128 buyerAmount = mul(amount, _buyerPercent)/100;
    uint128 sellerAmount = mul(amount, sub(100, _buyerPercent))/100;
    uint128 buyerfindEtherGasFee = mul(escrowDatabase[_key].findEtherGasFee, _buyerPercent)/100;
    uint128 sellerfindEtherGasFee = mul(escrowDatabase[_key].findEtherGasFee, sub(100, _buyerPercent))/100;
    EscalationResolved(escrowDatabase[_key].maker, escrowDatabase[_key].taker, _key);
    delete escrowDatabase[_key];
    transferFunds(taker, buyerAmount, _fee, buyerfindEtherGasFee);
    transferFunds(maker, sellerAmount, 0, sellerfindEtherGasFee);
  }

  function buyerMarkPaid(bytes32 _key) external returns(bool){
    require(msg.sender == escrowDatabase[_key].taker);
    return markPaid(_key);
  }

  function sellerCancel(bytes32 _key) external returns(bool){
    require(msg.sender == escrowDatabase[_key].maker);
    uint128 _findEtherGasFee = escrowDatabase[_key].findEtherGasFee;
    return cancel(_key, _findEtherGasFee);
  }

  function sellerRelease(bytes32 _key, uint128 _fee) external returns(bool){
    require(msg.sender == escrowDatabase[_key].maker);
    uint128 _findEtherGasFee = escrowDatabase[_key].findEtherGasFee;
    return release(_key, _findEtherGasFee, _fee);
  }

  function buyerRefund(bytes32 _key) external returns(bool){
    require(msg.sender == escrowDatabase[_key].taker);
    uint128 _findEtherGasFee = escrowDatabase[_key].findEtherGasFee;
    return refund(_key, _findEtherGasFee);
  }

  function escrowEscalation(bytes32 _key) external returns(bool){
    require(msg.sender == escrowDatabase[_key].taker || msg.sender == escrowDatabase[_key].maker);
    return escalation(_key);
  }

  function relayerBuyerMarkPaid(bytes32 _key) onlyRelayer external returns(bool){
    /* require(escrowDatabase[_key].taker == ecrecover("msg")); */
    escrowDatabase[_key].findEtherGasFee = add(escrowDatabase[_key].findEtherGasFee, mul(31600, uint128(tx.gasprice)));
    return markPaid(_key);
  }

  function relayerSellerCancel(bytes32 _key) onlyRelayer external returns(bool){
    /* require(escrowDatabase[_key].maker == ecrecover("msg")); */
    escrowDatabase[_key].findEtherGasFee = add(escrowDatabase[_key].findEtherGasFee, mul(39973, uint128(tx.gasprice)));
    return cancel(_key, escrowDatabase[_key].findEtherGasFee);
  }

  function relayerSellerRelease(bytes32 _key, uint128 _fee) onlyRelayer external returns(bool){
    /* require(escrowDatabase[_key].maker == ecrecover("msg")); */
    escrowDatabase[_key].findEtherGasFee = add(escrowDatabase[_key].findEtherGasFee, mul(40235, uint128(tx.gasprice)));
    return release(_key, escrowDatabase[_key].findEtherGasFee, _fee);
  }

  function relayerBuyerRefund(bytes32 _key) onlyRelayer external returns(bool){
    /* require(escrowDatabase[_key].taker == ecrecover("msg")); */
    escrowDatabase[_key].findEtherGasFee = add(escrowDatabase[_key].findEtherGasFee, mul(40029, uint128(tx.gasprice)));
    return refund(_key, escrowDatabase[_key].findEtherGasFee);
  }

  function relayerEscrowEscalation(bytes32 _key) onlyRelayer external returns(bool){
    /* require(escrowDatabase[_key].taker == ecrecover("msg") || escrowDatabase[_key].maker == ecrecover("msg")); */
    escrowDatabase[_key].findEtherGasFee = add(escrowDatabase[_key].findEtherGasFee, mul(40166, uint128(tx.gasprice)));
    return escalation(_key);
  }

  function checkStatus(bytes32 _key) constant returns (uint128){
    return escrowDatabase[_key].status;
  }


  function transferFunds(address _user, uint128 _amount, uint128 _fee, uint128 _findEtherGasFee) private{
    uint128 _escrowFee = add(mul(_fee, _amount)/100, _findEtherGasFee);
    totalFeeForWithdrawal += _escrowFee;
    _user.transfer(sub(_amount, _escrowFee));
    //check for gas fee
  }

  function(){
    revert();
  }

  function checkFeeForWithdrawal() onlyOwner constant external returns(uint128){
    return totalFeeForWithdrawal;
  }

  function withdrawFeeCollected(address _to, uint128 _amount) onlyOwner external{
    require(_amount <= totalFeeForWithdrawal);
    totalFeeForWithdrawal -= _amount;
    _to.transfer(_amount);
  }

  function changeOwner(address newOwner) onlyOwner external {
    owner = newOwner;
  }

  function addArbiter(address newArbiter) onlyOwner notInArbiter(newArbiter) external {
    arbiterDatabase[newArbiter] = true;
  }

  function addRelayer(address newRelayer) onlyOwner notInRelayer(newRelayer) external {
    relayerDatabase[newRelayer] = true;
  }

  function removeArbiter(address arbiter) onlyOwner inArbiter(arbiter) external {
    delete arbiterDatabase[arbiter];
  }

  function removeRelayer(address relayer) onlyOwner inRelayer(relayer) external {
    delete relayerDatabase[relayer];
  }
}
  /* function changeArbiter(address newArbiter) onlyOwner external {
    arbiter = newArbiter;
  }

  function changeFee(uint128 newFee) onlyOwner external {
    fee = newFee;
  }

  function changeMinimimumTimeBeforeCancel(uint128 newTime) onlyOwner external {
    minimimumTimeBeforeCancel = newTime;
  }
} */
