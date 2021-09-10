# Aave - Uniswap

Contract address
`0xee067738A18C8ff49e3Fe34E9b3622744B1E71ab`

Constructor params
```
ILendingPoolAddressesProvider
0x88757f2f99175387ab4c6a4b3067c77a695b0349

IProtocolDataProvider
0x3c73A5E5785cAC854D468F727c606C07488a29D6

IUniswapV2Router02
0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
```

Pending improves / fixes
* There is no test coverage
* Minimum amounts when adding/removing liquidity from Uniswap are not set
* Removing liquidity from Uniswap and depositing the tokens into Aave doesn't work - the logic is there but there is an error somewhere. Should be something silly