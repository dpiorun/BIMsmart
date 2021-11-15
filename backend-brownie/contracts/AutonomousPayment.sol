//SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

/// @title Smart contract for settlement a contract betweeen contractor and subcontractor
/// @author Klaatu Carpenter
/// @notice this contract is suitable just for two users: contractor and subcontractor
/// @custom:experimental This is experimental contract
contract AutonomousPayment is Ownable, ERC721URIStorage {

  address payable public subcontractor;
  
  using Counters for Counters.Counter;
  Counters.Counter private paymentIDs;

  /// @notice input data specific for the project
  struct InputData {
    string CID_listOfElementsAndGUIDs;
    string CID_asBuiltBIM;
    string CID_scheduleOfValues;
    string CID_rawProgressData;
    string CID_solutionUsedForProgressEvaluation;
    uint256 value;
    bool paymentDone;
  }

  struct LienToken {
    string CID_asBuiltBIM;
  }
  
  /// @notice a list storing all of the lien tokens
  LienToken[] public lienTokens;

  uint256 numPayment;
  mapping (uint256 => InputData) payments; 

  enum State { Created, InitialDataProvided, Agreed, Aborted }
  // The state variable has a default value of the first member, `State.created`
  State public state;

  error OnlySubcontractor(string);
  error InvalidState(string);

  modifier onlySubcontractor() {
      if (msg.sender != subcontractor)
          revert OnlySubcontractor("Only the subcontractor can call this function");
      _;
  }

  modifier inState(State state_) {
      if (state != state_)
          revert InvalidState("The function cannot be called at the current state");
      _;
  }

  event Aborted();
  event PaymentDeposited();
  event ContractConfirmed();
  event PaymentRequested(uint256);
  event PaymentSent(uint256);
  event NotSufficientContractBalance();
  event InitialDataProvided();
  event issueLienTokenMintedToSubcontractor(uint256);
  event issueLienTokenMintedToOwner(uint256);

  constructor(string memory _projectName, string memory _projectNameShorthandName, address _subcontractor) ERC721(_projectName, _projectNameShorthandName) {
    subcontractor = payable(_subcontractor);
  }

  /// @notice Contractor (who should be also owner) deposits agreed value
  /// @dev it would be suitable to check if the contract_value is equal to the value in agreement (job for Chainlink?)
  function deposit() external payable {
      emit PaymentDeposited();
  }

  /*  
    @notice Abort the contract and reclaim the ether.
    Can only be called by the contractor before
    the contract is agreed.
  */

  /// @notice provide initial data for the contract
 function provideInitialData(
    string memory _CID_listOfElementsAndGUIDs,
    string memory _CID_scheduleOfValues,
    string memory _CID_solutionUsedForProgressEvaluation)
    external 
    onlyOwner 
    inState(State.Created)
    returns (uint256 paymentID) {
      paymentID = paymentIDs.current();
      InputData storage initial = payments[paymentID];
      initial.CID_listOfElementsAndGUIDs = _CID_listOfElementsAndGUIDs;
      initial.CID_scheduleOfValues = _CID_scheduleOfValues;
      initial.CID_solutionUsedForProgressEvaluation = _CID_solutionUsedForProgressEvaluation;
      initial.paymentDone = true;
      state = State.InitialDataProvided;
      emit InitialDataProvided();
 }

  function abort() external onlyOwner inState(State.InitialDataProvided)
    {
      emit Aborted();
      state = State.Aborted;
      address payable contractor = payable(owner());
      contractor.transfer(address(this).balance);
    }

  /// @notice Confirm the contract as subcontractor.
  /// It changes the state to Agreed.
  function confirmContract() external onlySubcontractor inState(State.InitialDataProvided) 
  {
      state = State.Agreed;
      emit ContractConfirmed();
  }

  /// @notice receiveUpdate ensures the information is correctly formatted 
  /// before it triggers internal funtions to initiate on-chain payment settlement
  function receiveUpdate(
    string memory _CID_listOfElementsAndGUIDs,
    string memory _CID_asBuiltBIM,
    string memory _CID_scheduleOfValues,
    string memory _CID_rawProgressData,
    string memory _CID_solutionUsedForProgressEvaluation,
    uint256 _value) 
    external 
    inState(State.Agreed) 
    returns (uint256 paymentID) {
      require(
        (keccak256(abi.encodePacked(_CID_listOfElementsAndGUIDs)) == keccak256(abi.encodePacked(payments[0].CID_listOfElementsAndGUIDs)) &&
        keccak256(abi.encodePacked(_CID_scheduleOfValues)) == keccak256(abi.encodePacked(payments[0].CID_scheduleOfValues)) && 
        keccak256(abi.encodePacked(_CID_solutionUsedForProgressEvaluation)) == keccak256(abi.encodePacked(payments[0].CID_solutionUsedForProgressEvaluation))),
        "Input data validation failed"
      );
      
      /// @notice payment settlement
      paymentIDs.increment();
      paymentID = paymentIDs.current();
      InputData storage payment = payments[paymentID];
      payment.CID_listOfElementsAndGUIDs = _CID_listOfElementsAndGUIDs;
      payment.CID_asBuiltBIM = _CID_asBuiltBIM;
      payment.CID_scheduleOfValues = _CID_scheduleOfValues;
      payment.CID_rawProgressData = _CID_rawProgressData;
      payment.CID_solutionUsedForProgressEvaluation = _CID_solutionUsedForProgressEvaluation;
      payment.value = _value; 
      payment.paymentDone = false;

      transferPayValue(paymentID);
      issueLienToken(paymentID);
  }

  function transferPayValue(uint256 _paymentID) internal {
    if (payments[_paymentID].value <= address(this).balance) {
      payments[_paymentID].paymentDone = true;
      emit PaymentSent(_paymentID);
      subcontractor.transfer(payments[_paymentID].value);
    } else {
      emit NotSufficientContractBalance();
    }
    
  }

  /// @dev _paymentID is also the tokenID 
  function issueLienToken(uint256 _paymentID) internal {
    LienToken memory lienToken = LienToken(
      payments[_paymentID].CID_asBuiltBIM
    );
    lienTokens.push(lienToken);
    if (payments[_paymentID].paymentDone) {
      _safeMint(owner(), _paymentID);
      emit issueLienTokenMintedToSubcontractor(_paymentID);
    } else {
      _safeMint(subcontractor, _paymentID);    
      emit issueLienTokenMintedToOwner(_paymentID);
    }
    
  } 
  
  

  /// @notice get functions
  
  function getContractBalance() public view returns(uint256) {
    return address(this).balance;
  }

  function getNumberOfPaymentsDone() public view returns(uint256) {
    return numPayment;
  }

  function getLienToken(uint256 _paymentID) public view returns(uint256, string memory) {
    return (
      _paymentID,
      lienTokens[_paymentID].CID_asBuiltBIM
    );
  }

  function getPaymentInfo(uint256 _paymentID) public view returns(
    string memory,
    string memory,
    string memory,
    string memory,
    string memory,
    uint256,
    bool
  ) {
    return (
      payments[_paymentID].CID_listOfElementsAndGUIDs,
      payments[_paymentID].CID_asBuiltBIM,
      payments[_paymentID].CID_scheduleOfValues,
      payments[_paymentID].CID_rawProgressData,
      payments[_paymentID].CID_solutionUsedForProgressEvaluation,
      payments[_paymentID].value,
      payments[_paymentID].paymentDone
    );
  }
}