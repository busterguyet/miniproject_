/ SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract realEstate {


	uint8 public avgBlockTime;                          
	uint8 private decimals;                             
	uint8 public tax;                               	
	uint8 public rentalLimitMonths;                     
	uint256 public rentalLimitBlocks;                   
	uint256 constant private MAX_UINT256 = 2**256 - 1; 
	uint256 public totalTokens;                        
	uint256 public totalTokens2;                       
	uint256 public monthlyrent;                        
	uint256 public accumulated;                         
	uint256 public blocksPer30Day;                    
	uint256 public rentalstart;                       
  	uint256 public occupiedUntill;                  
	uint256 private _taxdeduct;                       


	string public name;                                
	string public symbol;                              
	address public admin = payable(msg.sender);    	            
	address public assetOwner;                  
  	address public tenant;                             

	address[] public investors;                     

	mapping (address => uint256) public revenues;       
	mapping (address => uint256) public tokens;         
	mapping (address => mapping (address => uint256)) private approval;   
	mapping (address => uint256) public rentpaidUntill; 
	mapping (address => uint256) public tokensOffered;  
    mapping (address => uint256) public tokenSellPrice; 






	event TokenTransfer(address indexed from, address indexed to, uint256 tokens);
	event Seizure(address indexed seizedfrom, address indexed to, uint256 tokens);
	event ChangedTax(uint256 NewTax);
	event assetowner(address NewassetOwner);
	event Newinvestor(address investorAdded);
	event CurrentlyEligibletoPayRent(address Tenant);
	event PrePayRentLimit (uint8 Months);
	event AvgBlockTimeChangedTo(uint8 s);
	event monthlyrentSetTo (uint256 WEIs);
	event investorBanned (address banned);
	event RevenuesDistributed (address tokenholder, uint256 gained, uint256 total);
	event Withdrawal (address tokenholder, uint256 withdrawn);
	event Rental (uint256 date, address renter, uint256 rentPaid, uint256 tax, uint256 distributableRevenue, uint256 rentedFrom, uint256 rentedUntill);
	event TokensOffered(address Seller, uint256 AmmountTokens, uint256 PricePerToken);
	event TokensSold(address Seller, address Buyer, uint256 TokensSold,uint256 PricePerToken);


	constructor (string memory _assetID, string memory _assetSymbol, address _assetOwner, uint8 _tax, uint8 _avgBlockTime,uint _tokens_) {
		tokens[_assetOwner] = 100;                  
		totalTokens = _tokens_;                                 
		totalTokens2 = totalTokens**2;                     
		name = _assetID;
		decimals = 0;
		symbol = _assetSymbol;
		tax = _tax;                                        
		assetOwner = _assetOwner;
		investors.push(admin);                             
		investors.push(assetOwner);
		approval[assetOwner][admin] = MAX_UINT256;      
		avgBlockTime = _avgBlockTime;                       
	    rentalLimitMonths = 12;                                   
	    rentalLimitBlocks = rentalLimitMonths * blocksPer30Day;
	}



	modifier onlyadmin{
	  require(payable(msg.sender) == admin);
	  _;

	}
	modifier onlyPropOwner{
	    require(payable(msg.sender) == assetOwner);
	    _;
	}
	modifier isMultipleOf{
	   require(msg.value % totalTokens2 == 0);              
     	    _;
	}
	modifier eligibleToPayRent{                            
	    require(payable(msg.sender) == tenant);
	    _;
	}


	
//viewable functions returns values.

	function showTokensOf(address _owner) public view returns (uint256 balance) {       
		return tokens[_owner];
	}

	 function isinvestor(address _address) public view returns(bool, uint256) {      //shows whether someone is a investor.
	    for (uint256 i = 0; i < investors.length; i += 1){
	        if (_address == investors[i]) return (true, i);
	    }
	    return (false, 0);
	 }

    function currentTenantCheck (address _tenantcheck) public view returns(bool,uint256){               //only works if from block.number on there is just one tenant, otherwise tells untill when rent is paid.
        require(occupiedUntill == rentpaidUntill[tenant], "invalid tenant address");
        if (rentpaidUntill[_tenantcheck] > block.number){
        uint256 daysRemaining = (rentpaidUntill[_tenantcheck] - block.number)*avgBlockTime/86400;       //86400 seconds in a day.
        return (true, daysRemaining);                                                                   //gives tenant paid status true or false and days remaining
        }
        else return (false, 0);
    }




    function addinvestor(address _investor) public onlyadmin {      
		(bool _isinvestor, ) = isinvestor(_investor);
		if (!_isinvestor) investors.push(_investor);
		approval[_investor][admin] = MAX_UINT256;                       
		emit Newinvestor (_investor);
    }

	function baninvestor(address _investor) public onlyadmin {          // can remove investor from investors array and...
	    (bool _isinvestor, uint256 s) = isinvestor(_investor);
	    if (_isinvestor){
	        investors[s] = investors[investors.length - 1];
	        investors.pop();
	        seizureFrom (_investor, payable(msg.sender),tokens[_investor]);    //...seizes tokens
	        emit investorBanned(_investor);
	    }
	}

	function setTax (uint8 _x) public onlyadmin {                             //set new tax rate (for incoming rent being taxed with %)
	   require( _x <= 100, "select a valid tax rate" );
	   tax = _x;
	   emit ChangedTax (tax);
	}

	function SetAvgBlockTime (uint8 _sPerBlock) public onlyadmin{         //we do not have a forgery proof time measurement in Ethereum. Therefore we count the ammount of blocks. One Block equals to 13s but this can be changed by the adminernment.
	    require(_sPerBlock > 0, " enter a Value above 0");
	    avgBlockTime = _sPerBlock;
	    blocksPer30Day = (60*60*24*30) / avgBlockTime;
	    emit AvgBlockTimeChangedTo (avgBlockTime);
	}

   function distribute() public onlyadmin {       
        uint256 _accumulated = accumulated;
        for (uint256 s = 0; s < investors.length; s += 1){
            address investor = investors[s];
            uint256 _tokens = showTokensOf(investor);
            uint256 ethertoreceive = (_accumulated/(totalTokens))*_tokens;
            accumulated = accumulated - ethertoreceive;
            revenues[investor] = revenues[investor] + ethertoreceive;
            emit RevenuesDistributed(investor,ethertoreceive, revenues[investor]);
        }
   }



	function seizureFrom(address _from, address _to, uint256 _value) public returns (bool success) {           //adminernment has unlimited allowance, therefore  can seize all assets from every investor. Function also used to buyTokens from investor.
		uint256 allowance = approval[_from][payable(msg.sender)];
		require(tokens[_from] >= _value && allowance >= _value);
		tokens[_to] += _value;
		tokens[_from] -= _value;
		if (allowance < MAX_UINT256) {
			approval[_from][payable(msg.sender)] -= _value;
		}
		emit Seizure(_from, _to, _value);
		return true;
	}



	function canPayRent(address _tenant) public onlyPropOwner{               
	     tenant = _tenant;
	     emit CurrentlyEligibletoPayRent (tenant);
	}
	function limitadvancedrent(uint8 _monthstolimit) onlyPropOwner public{      
	    rentalLimitBlocks = _monthstolimit *blocksPer30Day;
	    emit PrePayRentLimit (_monthstolimit);
	}

    function setmonthlyrent(uint256 _rent) public onlyPropOwner{              
	    monthlyrent = _rent;
	    emit monthlyrentSetTo (monthlyrent);
    }



    function offerTokens(uint256 _tokensOffered, uint256 _tokenSellPrice) public{       
        (bool _isinvestor,) = isinvestor(payable(msg.sender));//checks if the investor is true
        require(_isinvestor);//requires isinvestor to be true
        require(_tokensOffered <= tokens[payable(msg.sender)]);//offered shares must be less than the senders shares
        tokensOffered[payable(msg.sender)] = _tokensOffered;
        tokenSellPrice[payable(msg.sender)] = _tokenSellPrice;//in wei
        emit TokensOffered(payable(msg.sender), _tokensOffered, _tokenSellPrice);
    }

    function buyTokens (uint256 _tokensToBuy, address payable _from) public payable{    
        (bool _isinvestor,) = isinvestor(payable(msg.sender));
        require(_isinvestor);
        require(msg.value == _tokensToBuy * tokenSellPrice[_from] && _tokensToBuy <= tokensOffered[_from] && _tokensToBuy <= tokens[_from] &&_from != payable(msg.sender)); 
        approval[_from][payable(msg.sender)] = _tokensToBuy;
        seizureFrom(_from, payable(msg.sender), _tokensToBuy);
        tokensOffered[_from] -= _tokensToBuy;
        _from.transfer(msg.value);
        emit TokensSold(_from, payable(msg.sender), _tokensToBuy,tokenSellPrice[_from]);
    }

	function transfer(address _recipient, uint256 _amount) public returns (bool) {     
        (bool isinvestorX, ) = isinvestor(_recipient);
	    require(isinvestorX);
	    require(tokens[payable(msg.sender)] >= _amount);
	    tokens[payable(msg.sender)] -= _amount;
	    tokens[_recipient] += _amount;
	    emit TokenTransfer(payable(msg.sender), _recipient, _amount);
	    return true;
	 }



	function claimOwnership () public {            
		require(tokens[payable(msg.sender)] > (totalTokens /2) && payable(msg.sender) != assetOwner,"you must have less than 50% shares");
		assetOwner = payable(msg.sender);
		emit assetowner(assetOwner);
	}



   function withdraw() payable public {          
        uint256 revenue = revenues[payable(msg.sender)];
        revenues[payable(msg.sender)] = 0;//empties the reserves
        (payable(msg.sender)).transfer(revenue);//transfer revenue in the revenues array to the message sender
        emit Withdrawal(payable(msg.sender), revenue);
   }



    function payRent(uint8 _months) public payable isMultipleOf eligibleToPayRent{          
        uint256  _rentdue  = _months * monthlyrent;
        uint256  _additionalBlocks  = _months * blocksPer30Day;
        require (msg.value == _rentdue && block.number + _additionalBlocks < block.number + rentalLimitBlocks);     
        _taxdeduct = (msg.value/totalTokens * tax);                                
        accumulated += (msg.value - _taxdeduct);                                    
        revenues[admin] += _taxdeduct;                                                
        if (rentpaidUntill[tenant] == 0 && occupiedUntill < block.number) {         
            rentpaidUntill[tenant] = block.number + _additionalBlocks;              
            rentalstart = block.number;
        }
        else if (rentpaidUntill[tenant] == 0 && occupiedUntill > block.number) {    
            rentpaidUntill[tenant] = occupiedUntill + _additionalBlocks;            
            rentalstart = occupiedUntill;
        }
        else if ( rentpaidUntill[tenant] > block.number) {                          
            rentpaidUntill[tenant] += _additionalBlocks;                            
            rentalstart = occupiedUntill;
        }
        else if (rentpaidUntill[tenant] < block.number && occupiedUntill>block.number) {    
            rentpaidUntill[tenant] = occupiedUntill +_additionalBlocks;                     
            rentalstart = occupiedUntill;
        }
        else if (rentpaidUntill[tenant] < block.number && occupiedUntill<block.number) {    
            rentpaidUntill[tenant] = block.number + _additionalBlocks;                      
            rentalstart = block.number;                                                    
        }
        occupiedUntill  = rentpaidUntill[tenant];                                          
        emit Rental (block.timestamp, payable(msg.sender), msg.value, _taxdeduct, (msg.value - _taxdeduct), rentalstart, occupiedUntill);
    } 



    receive () external payable {                  
        (payable(msg.sender)).transfer(msg.value);
        }
}
