//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "hardhat/console.sol";

contract MultiSigWallet {
	enum UserRoles {
		Member,
		Voter
	}
	
	struct Transaction {
		address destination;
		uint value;
		bytes data;
		bool executed;
	}

	struct Proposal {
		address proposer;
		address deleting_address;
		bool executed;
	}

	struct ChangeProposal {
		address proposer;
		uint required_votes;
		uint amount_above_voter;
		bool executed;
	}

	struct User {
		address owner;
		uint amount_invested;
		UserRoles user_role;
	}

	mapping(uint => Transaction) transactions;
	mapping(uint => mapping(address => bool)) confirmations;
	mapping(address => bool) isMember;
	mapping(address => bool) isVoter;
	mapping(address => User) musers;
	uint transactionCount;
	User[] users;

	mapping(uint => Proposal) proposals;
	mapping(uint => mapping(address => bool)) proposal_confirmations;
	uint proposalCount;

	mapping(uint => ChangeProposal) change_proposals;
	mapping(uint => mapping(address => bool)) change_proposal_confirmations;
	uint changeProposalCount;
	
	address public owner;
	uint public amount_above_voter;
	uint public required_votes;

	// Events

	event UserAdd(address indexed user);
	event UserRemoveProposal(address indexed user);
	event UserRemove(address indexed user);
	event TransactionAdd(uint indexed transactionId);
	event TransactionRemove(uint indexed transactionId);
	event TransactionSuccess(uint indexed transactionId);
	event TransactionFailure(uint indexed transactionId);
	event Deposit(address indexed sender, uint value);
	event ChangeRoleAmount(uint amount_above_owner);
	event ChangeMaxVote(uint required_votes);
	event ProposalConfirm(uint indexed proposalId, address indexed user);
	event ProposalRevoke(uint indexed proposalId, address indexed user);
	event TransactionConfirm(uint indexed transactionId, address indexed user);
	event TransactionRevoke(uint indexed transactionId, address indexed user);
	event AddChangeProposal(uint indexed proposalId);
	event ChangeProposalConfirm(uint indexed proposalId, address indexed user);
	event ChangeProposalRevoke(uint indexed proposalId, address indexed user);
	event ChangeProposalExecuted(uint indexed proposalId);

	modifier notAnOwner() {
		require(!isVoter[msg.sender] && !isMember[msg.sender], "notAnOwner");
		_;
	}

	modifier onlyOwner(address _owner) {
		require(msg.sender == owner, "onlyOwner");
		_;
	}

	modifier anOwner() {
		require(isVoter[msg.sender] || isMember[msg.sender], "anOwner");
		_;
	}

	modifier anVoter() {
		require(isVoter[msg.sender], "anVoter");
		_;
	}

	modifier transactionExists(uint transactionId) {
		require(transactions[transactionId].destination != address(0), "transactionExists");
		_;
	}

	modifier proposalExists(uint proposalId) {
		require(proposals[proposalId].proposer != address(0), "proposalExists");
		_;
	}

	modifier proposal_confirmed(uint proposalId, address _owner) {
		require(proposal_confirmations[proposalId][_owner], "proposal_confirmed");
		_;
	}

	modifier not_proposal_confirmed(uint proposalId, address _owner) {
		require(!proposal_confirmations[proposalId][_owner], "not_proposal_confirmed");
		_;
	}

	modifier proposal_executed(uint proposalId) {
		require(proposals[proposalId].executed, "proposal_executed");
		_;
	}

	modifier not_proposal_executed(uint proposalId) {
		require(!proposals[proposalId].executed, "not_proposal_executed");
		_;
	}

	modifier notConfirmed(uint transactionId, address _owner) {
		require(!confirmations[transactionId][_owner], "notConfirmed");
		_;
	}

	modifier confirmed(uint transactionId, address _owner) {
		require(confirmations[transactionId][_owner], "confirmed");
		_;
	}

	modifier notNull(address destination) {
		require(!(destination == address(0)), "notNull");
		_;
	}

	modifier notExecuted(uint transactionId) {
		require(!transactions[transactionId].executed, "notExecuted");
		_;
	}

	modifier executed(uint transactionId) {
		require(transactions[transactionId].executed, "executed");
		_;
	}

    modifier checkBalance(uint value) {
        require(address(this).balance > value, "Balance is Low");
        _;
    }

	modifier changeProposalExists(uint _changeProposalId) {
		require(change_proposals[_changeProposalId].proposer != address(0), "Proposal Doesn't Exists");
		_;
	} 

	modifier notChangeProposalExists(uint _changeProposalId) {
		require(change_proposals[_changeProposalId].proposer == address(0), "Proposal Doesn't Exists");
		_;
	} 
	
	modifier changeProposalConfirmed(uint _changeProposalId, address sender) {
		require(change_proposal_confirmations[_changeProposalId][sender], "Proposal is not confirmed by sender!");
		_;
	}
	
	modifier notChangeProposalConfirmed(uint _changeProposalId, address sender) {
		require(!change_proposal_confirmations[_changeProposalId][sender], "Proposal already confirmed by sender!");
		_;
	}
	
	modifier changeProposalExecuted(uint _changeProposalId) {
		require(change_proposals[_changeProposalId].executed, "Proposal not executed");
		_;
	}
	
	modifier notChangeProposalExecuted(uint _changeProposalId) {
		require(!change_proposals[_changeProposalId].executed, "Proposal already executed");
		_;
	}

	// Functions

	// @dev - will create a new user along with a new wallet
	constructor (uint _amount_above_voter, uint _required_votes) payable {
		require(msg.value > 0, "Please Pay your Share in the investment fund!");
		
		owner = msg.sender;
		amount_above_voter = _amount_above_voter;
		required_votes = _required_votes;

		User memory user = User(msg.sender, msg.value, UserRoles.Voter);

		users.push(user);
		musers[msg.sender] = user;
		isVoter[msg.sender] = true;
	}

	// @dev - will add members or voters
	function addUser() public payable notAnOwner {
		require(msg.value > 0, "You need to send some money to the SAFE");
		
		UserRoles role;
		
		if(msg.value >= amount_above_voter) {
			role = UserRoles.Voter;
			isVoter[msg.sender] = true;
		} else {
			role = UserRoles.Member;
			isMember[msg.sender] = true;
		}
		
		User memory user = User(msg.sender, msg.value, role);
		users.push(user);
		musers[msg.sender] = user;

		emit UserAdd(msg.sender);
	}

	// @dev - will add a proposal to remove members or voters
	function removeUserProposal(address _user) public anVoter {
		Proposal memory deleting_proposal = Proposal(msg.sender, _user, false);
		
		proposals[proposalCount] = deleting_proposal;
		addConfirmationProposal(proposalCount);
		proposalCount += 1;
		
		emit UserRemoveProposal(_user);
	}

	// @dev will remove members or voters
	function removeUser(uint _proposalId) public {
		require(isProposalConfirmed(_proposalId), "Proposal Not Confirmed Yet");
		
		Proposal storage deleting_proposal = proposals[_proposalId];
		User memory user = musers[deleting_proposal.deleting_address]; 

		if(user.amount_invested >= amount_above_voter) {
			isVoter[deleting_proposal.deleting_address] = false;
		} else {
			isMember[deleting_proposal.deleting_address] = false;
		}

		for(uint i=0;i<users.length;i++) {
			if(users[i].owner == deleting_proposal.deleting_address) {
				users[i] = users[users.length - 1];
				break;
			}
		}
		users.pop();

		if(required_votes > users.length) {
			required_votes = users.length;
		}

		emit UserRemove(deleting_proposal.deleting_address);

		deleting_proposal.executed = true;
	}

	// @dev - add proposal confirmation
	function addConfirmationProposal(uint _proposalId) public anOwner anVoter proposalExists(_proposalId) not_proposal_confirmed(_proposalId, msg.sender) {
		proposal_confirmations[_proposalId][msg.sender] = true;
		emit ProposalConfirm(_proposalId, msg.sender);
		removeUser(_proposalId);
	}

	// @dev - revoke proposal confirmation proposal 
	function revokeConfirmationProposal(uint _proposalId) public anOwner anVoter proposalExists(_proposalId) proposal_confirmed(_proposalId, msg.sender) not_proposal_executed(_proposalId) {
		proposal_confirmations[_proposalId][msg.sender] = false;
		emit ProposalRevoke(_proposalId, msg.sender);
	}

	// @dev - check if a proposal is confirmed
	function isProposalConfirmed(uint _proposalId) internal view proposalExists(_proposalId) returns (bool) {
		uint count = 0;
		
		for(uint i=0;i<users.length;i++) {
			address usr = users[i].owner;
			if(proposal_confirmations[_proposalId][usr]) {
				count += 1;
			}

			if(count == required_votes) {
				return true;
			}
		}

		if(count == required_votes) return true;
		else return false;
	}

	/// @dev Creates a Proposal to change required_votes and amount_to_vote
	function changeConstants(uint _required_votes, uint _amount_to_vote) public anOwner {
		ChangeProposal memory proposal = ChangeProposal(msg.sender, _required_votes, _amount_to_vote, false);
		change_proposals[changeProposalCount] = proposal;
		addConfirmationChangeProposal(changeProposalCount);
		emit AddChangeProposal(changeProposalCount);
		changeProposalCount += 1;
	}

	/// @dev add confirmation for changing constants
	function addConfirmationChangeProposal(uint _changeProposalId) public anVoter changeProposalExists(_changeProposalId) notChangeProposalConfirmed(_changeProposalId, msg.sender) notChangeProposalExecuted(_changeProposalId) {
		change_proposal_confirmations[_changeProposalId][msg.sender] = true;
		emit ChangeProposalConfirm(_changeProposalId, msg.sender);
		executeChangeProposal(_changeProposalId);
	}

	/// @dev revoke confirmation for changing constants
	function revokeConfirmationChangeProposal(uint _changeProposalId) public anVoter changeProposalExists(_changeProposalId) changeProposalConfirmed(_changeProposalId, msg.sender) notChangeProposalExecuted(_changeProposalId) {
		change_proposal_confirmations[_changeProposalId][msg.sender] = false;
		emit ChangeProposalRevoke(_changeProposalId, msg.sender);
	}

	/// @dev Check if a proposal is confirmed
	function isChangeProposalConfirmed(uint _changeProposalId) public view changeProposalExists(_changeProposalId) notChangeProposalExecuted(_changeProposalId) returns (bool) {
		uint count = 0;
		
		for(uint i=0;i<users.length;i++) {
			address usr = users[i].owner;
			if(change_proposal_confirmations[_changeProposalId][usr]) {
				count += 1;
			}

			if(count == required_votes) {
				return true;
			}
		}

		if(count == required_votes) return true;
		else return false;
	}

	/// @dev execute changes if change proposal is confirmed
	function executeChangeProposal(uint _changeProposalId) public anVoter changeProposalExists(_changeProposalId) notChangeProposalExecuted(_changeProposalId) {
		require(isChangeProposalConfirmed(_changeProposalId), "Change Proposal not confirmed yet");

		amount_above_voter = change_proposals[_changeProposalId].amount_above_voter;
		required_votes = change_proposals[_changeProposalId].required_votes;

		change_proposals[_changeProposalId].executed = true;

		emit ChangeProposalExecuted(_changeProposalId);
	}

	/// @dev - submit a transaction
	function submitTransaction(address _destination, uint _value, bytes memory _data) public checkBalance(_value) returns (uint transactionId) {
		transactionId = addTransaction(_destination, _value, _data);
		confirmTransaction(transactionId);
	}

	/// @dev Allows an owner to confirm a transaction.
    /// @param transactionId Transaction ID.
    function confirmTransaction(uint transactionId) public anOwner anVoter transactionExists(transactionId) notConfirmed(transactionId, msg.sender) {
        confirmations[transactionId][msg.sender] = true;
        emit TransactionConfirm(transactionId, msg.sender);
        executeTransaction(transactionId);
    }

	/// @dev Allows anyone to execute a confirmed transaction.
    /// @param transactionId Transaction ID.
    function executeTransaction(uint transactionId) public anOwner confirmed(transactionId, msg.sender) notExecuted(transactionId) {
        if (isConfirmed(transactionId)) {
            Transaction storage txn = transactions[transactionId];
            txn.executed = true;
            if (external_call(txn.destination, txn.value, txn.data.length, txn.data))
                emit TransactionSuccess(transactionId);
            else {
                emit TransactionFailure(transactionId);
                txn.executed = false;
            }
        }
    }

	// call has been separated into its own function in order to take advantage
    // of the Solidity's code generator to produce a loop that copies tx.data into memory.
    function external_call(address destination, uint value, uint dataLength, bytes memory data) internal returns (bool) {
        bool result;
        assembly {
            let x := mload(0x40)   // "Allocate" memory for output (0x40 is where "free memory" pointer is stored by convention)
            let d := add(data, 32) // First 32 bytes are the padded length of data, so exclude that
            result := call(
                sub(gas(), 34710),   // 34710 is the value that solidity is currently emitting
                                   // It includes callGas (700) + callVeryLow (3, to pay for SUB) + callValueTransferGas (9000) +
                                   // callNewAccountGas (25000, in case the destination address does not exist and needs creating)
                destination,
                value,
                d,
                dataLength,        // Size of the input (in bytes) - this is what fixes the padding problem
                x,
                0                  // Output is ignored, therefore the output size is zero
            )
        }
        return result;
    }

	/// @dev Returns the confirmation status of a transaction.
    /// @param transactionId Transaction ID.
    /// @return Confirmation status.
    function isConfirmed(uint transactionId) public view returns (bool)
    {
        uint count = 0;
        
		for(uint i=0;i<users.length;i++) {
			address usr = users[i].owner;
			if(confirmations[transactionId][usr]) {
				count += 1;
			}

			if(count == required_votes) {
				return true;
			}
		}

		if(count == required_votes) return true;
		else return false;
    }

	/// @dev Adds a new transaction to the transaction mapping, if transaction does not exist yet.
    /// @param destination Transaction target address.
    /// @param value Transaction ether value.
    /// @param data Transaction data payload.
    // @return Returns transaction ID.
    function addTransaction(address destination, uint value, bytes memory data) internal notNull(destination) returns (uint transactionId) {
        transactionId = transactionCount;
        transactions[transactionId] = Transaction({
            destination: destination,
            value: value,
            data: data,
            executed: false
        });
        transactionCount += 1;
        emit TransactionAdd(transactionId);
    }
}
