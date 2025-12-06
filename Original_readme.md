# Note that this is Branching off from him https://github.com/5l1v3r1/Minikeys

# Minikeys
### Pilot project searching for BitCoin [minikeys 22 characters](https://en.bitcoin.it/wiki/Mini_private_key_format) on the GPU Cuda.

- The program is under testing, errors are possible.
- Many thanks to [PawelGorny](https://github.com/PawelGorny/MinikeyCuda) in the development of the program. 
- Write a checkpoint every minute to a file fileStatus.txt

Run GPU TEST: ```MinikeyCuda.exe -input test_SkK5VPtmTm3mQKYaJQFRZP.txt -rangeStart SkK5VPtmTm3mQKYaJQ2222```</br>
Run GPU: ```MinikeyCuda.exe -input serie1.txt -rangeStart SkK5VPtmTm3mQKYaJQ2222```

![GPU](https://user-images.githubusercontent.com/82582647/157701762-0847585a-eecc-4ba9-95eb-f49906d8271a.png)

Run CPU random: ```MinikeyCuda.exe -input -input serie1.txt -random```

![CPU](https://user-images.githubusercontent.com/82582647/157701783-5a063b92-d217-4dec-ba0c-dbed414ada0c.png)


## Building
### Windows
- Microsoft Visual Studio Community 2019
- CUDA version [**10.22**](https://developer.nvidia.com/cuda-10.2-download-archive?target_os=Windows&target_arch=x86_64&target_version=10&target_type=exenetwork)
## License
- Rotor-Cuda is licensed under GPLv3.

## Donation
- phrutis BTC: bc1qh2mvnf5fujg93mwl8pe688yucaw9sflmwsukz9
- PawelGorny BTC: 34dEiyShGJcnGAg2jWhcoDDRxpennSZxg8
