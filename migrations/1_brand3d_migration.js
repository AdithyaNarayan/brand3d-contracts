// require('openzeppelin-test-helpers/configure')({web3})
// const {singletons} = require('openzeppelin-test-helpers')

const Brand3D = artifacts.require('Brand3D')
const Brand3DTourAndCustody = artifacts.require('Brand3DTourAndCustody')

module.exports = async function(deployer, _network, accounts) {
  // await singletons.ERC1820Registry(accounts[0]);

  await deployer.deploy(Brand3DTourAndCustody,
                        "The development of Nike Prints and Pattern", "NIKEPP");

  await deployer.deploy(Brand3D, 1000,
                        [ accounts[0], Brand3DTourAndCustody.address ]);

  const deployedCustody = await Brand3DTourAndCustody.deployed();
  await deployedCustody.setTokenAddress(Brand3D.address);
}
