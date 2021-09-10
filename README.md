# Aave - Uniswap

Contract address `0xee067738A18C8ff49e3Fe34E9b3622744B1E71ab`

Pending improves / fixes
* There is no test coverage
* Minimum amounts when adding/removing liquidity from Uniswap are not set
* Removing liquidity from Uniswap and depositing the tokens into Aave doesn't work - the logic is there but there is an error somewhere. Should be something silly