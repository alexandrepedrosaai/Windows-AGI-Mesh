Add files via upload
Add files via upload Add files via upload (#555) This pull request adds a comprehensive se… (#559) …t of new quantum benchmark case definitions to the Azure/benchmarks/cases directory. Each case specifies parameters for running benchmarks on various quantum hardware backends and simulators, covering a range of qubit counts, angles, and providers. These additions will enable broader and more systematic testing across different quantum platforms. **New benchmark case additions:** *Simulators and Microsoft backends:* - Added cases for 2, 4, 6, and 8 qubits using the microsoft.simulator.full-state backend (case_02, case_03, case_04, case_10, case_11, case_13). [[1]](diffhunk://#diff-493cedcd4b00e9e887f9525e89a3772d1326ff719b57bbaeaeb6edcbb1bdaa31R1-R18) [[2]](diffhunk://#diff-002a6d122c4844fa7d255143ba42635e3905f6bcc404676476852d8fa1cedba6R1-R18) [[3]](diffhunk://#diff-86e06e47d92a29d4573eaf0b3d821942e374eb4b30ad68458667ed733210fda5R1-R18) [[4]](diffhunk://#diff-40b241e7e28551de5701e06985df9e6ed9c4169af179aa8e3d5d671dff1e5e2bR1-R18) [[5]](diffhunk://#diff-3e5704fa51e1c30e4c75aa90932c29cfcce370d268ae85659d24e8f3b4da48b7R1-R18) [[6]](diffhunk://#diff-a07b486fe6be7ae71230ae426e1639393ed5a3433487f6e36c9b4fcc3a66e818R1-R18) *Other hardware backends:* - Added cases for specific hardware providers, including microsoft.majorana-1 (case_05, case_12), quantinuum.helios (case_06), ibm.nighthawk-r2 (case_07), ionq.forte-1 (case_08), aqt.pine (case_09), pasqal.emu-tn (case_14), and rigetti.ankaa-9q-3 (case_15). [[1]](diffhunk://#diff-e0f4de109a1c2072b8ab76f0bc03dcf6442ab0594558807e5d2bf1bbda4b33cdR1-R18) [[2]](diffhunk://#diff-4f22423ae7b8707a1309b28ac0bd9e71eb774a860870e45bc0dc33bf4d87a9d3R1-R18) [[3]](diffhunk://#diff-7d172808e26da484dd5eaa097d5a9dc30bef25d96d5c92f6f18134fd1a57f323R1-R18) [[4]](diffhunk://#diff-127f0b5f6f1caa81033ed729d45999609b461ab0d5b2e9c740144acd6b364cd4R1-R18) [[5]](diffhunk://#diff-0a9ec7b0fbcac59f25d0e391626a91df631ac5a16b53d302b0e607edc26f4dabR1-R18) [[6]](diffhunk://#diff-a836e176f67deccddbd50c635ffd250ee9a948e66d4133106c7c5c67caa304b9R1-R18) [[7]](diffhunk://#diff-c75b87be5a07c8a10d6fbfde8a378ea1d1383b8262b901fab37e560ba56f62a2R1-R18) [[8]](diffhunk://#diff-b19f9e934b2634d15ced32d6c877dcb92d7789de68b1c0e838e7cda41485d725R1-R18) *Parameter diversity:* - Cases vary in qubit and ancilla counts, rotation angles (theta_z, theta_y), shot counts, and target backends to ensure a broad coverage of benchmark scenarios. (All references above) *Consistent structure:* - Each case file includes metadata such as case_id, case_name, thresholds, expected means, timeout, and tags for automated test selection. (All references above) --------- Co-authored-by: Nasa <hq-open-innovation@mail.nasa.gov> Co-authored-by: Copilot Autofix powered by AI <62310815+github-advanced-security[bot]@users.noreply.github.com> Co-authored-by: Copilot Autofix powered by AI <175728472+Copilot@users.noreply.github.com> Co-authored-by: azure-verified-modules[bot] <187664033+azure-verified-modules[bot]@users.noreply.github.com> Co-authored-by: Deleted user <10137+ghost@users.noreply.github.com> Co-authored-by: microsoft-github-policy-service[bot] <77245923+microsoft-github-policy-service[bot]@users.noreply.github.com> Co-authored-by: Microsoft <opensource@microsoft.com> Co-authored-by: Microsoft <dev@microsoft.com> Co-authored-by: azurecla <azclasa@microsoft.com> Co-authored-by: Contributions <enhanceprovenance@microsoft.com>  Add files via upload (#555) This pull request adds a comprehensive set of new quantum benchmark case definitions to the Azure/benchmarks/cases directory. Each case specifies parameters for running benchmarks on various quantum hardware backends and simulators, covering a range of qubit counts, angles, and providers. These additions will enable broader and more systematic testing across different quantum platforms.  **New benchmark case additions:**  *Simulators and Microsoft backends:* - Added cases for 2, 4, 6, and 8 qubits using the microsoft.simulator.full-state backend (case_02, case_03, case_04, case_10, case_11, case_13).  [[1]](diffhunk://#diff-493cedcd4b00e9e887f9525e89a3772d1326ff719b57bbaeaeb6edcbb1bdaa31R1-R18) [[2]](diffhunk://#diff-002a6d122c4844fa7d255143ba42635e3905f6bcc404676476852d8fa1cedba6R1-R18) [[3]](diffhunk://#diff-86e06e47d92a29d4573eaf0b3d821942e374eb4b30ad68458667ed733210fda5R1-R18) [[4]](diffhunk://#diff-40b241e7e28551de5701e06985df9e6ed9c4169af179aa8e3d5d671dff1e5e2bR1-R18) [[5]](diffhunk://#diff-3e5704fa51e1c30e4c75aa90932c29cfcce370d268ae85659d24e8f3b4da48b7R1-R18) [[6]](diffhunk://#diff-a07b486fe6be7ae71230ae426e1639393ed5a3433487f6e36c9b4fcc3a66e818R1-R18)  *Other hardware backends:* - Added cases for specific hardware providers, including microsoft.majorana-1 (case_05, case_12), quantinuum.helios (case_06), ibm.nighthawk-r2 (case_07), ionq.forte-1 (case_08), aqt.pine (case_09), pasqal.emu-tn (case_14), and rigetti.ankaa-9q-3 (case_15).  [[1]](diffhunk://#diff-e0f4de109a1c2072b8ab76f0bc03dcf6442ab0594558807e5d2bf1bbda4b33cdR1-R18) [[2]](diffhunk://#diff-4f22423ae7b8707a1309b28ac0bd9e71eb774a860870e45bc0dc33bf4d87a9d3R1-R18) [[3]](diffhunk://#diff-7d172808e26da484dd5eaa097d5a9dc30bef25d96d5c92f6f18134fd1a57f323R1-R18) [[4]](diffhunk://#diff-127f0b5f6f1caa81033ed729d45999609b461ab0d5b2e9c740144acd6b364cd4R1-R18) [[5]](diffhunk://#diff-0a9ec7b0fbcac59f25d0e391626a91df631ac5a16b53d302b0e607edc26f4dabR1-R18) [[6]](diffhunk://#diff-a836e176f67deccddbd50c635ffd250ee9a948e66d4133106c7c5c67caa304b9R1-R18) [[7]](diffhunk://#diff-c75b87be5a07c8a10d6fbfde8a378ea1d1383b8262b901fab37e560ba56f62a2R1-R18) [[8]](diffhunk://#diff-b19f9e934b2634d15ced32d6c877dcb92d7789de68b1c0e838e7cda41485d725R1-R18)  *Parameter diversity:* - Cases vary in qubit and ancilla counts, rotation angles (theta_z, theta_y), shot counts, and target backends to ensure a broad coverage of benchmark scenarios. (All references above)  *Consistent structure:* - Each case file includes metadata such as case_id, case_name, thresholds, expected means, timeout, and tags for automated test selection. (All references above)  ---------  Co-authored-by: Nasa <hq-open-innovation@mail.nasa.gov> Co-authored-by: Copilot Autofix powered by AI <62310815+github-advanced-security[bot]@users.noreply.github.com> Co-authored-by: Copilot Autofix powered by AI <175728472+Copilot@users.noreply.github.com> Co-authored-by: azure-verified-modules[bot] <187664033+azure-verified-modules[bot]@users.noreply.github.com> Co-authored-by: Deleted user <10137+ghost@users.noreply.github.com> Co-authored-by: microsoft-github-policy-service[bot] <77245923+microsoft-github-policy-service[bot]@users.noreply.github.com> Co-authored-by: Microsoft <opensource@microsoft.com> Co-authored-by: Microsoft <dev@microsoft.com> Co-authored-by: azurecla <azclasa@microsoft.com> Co-authored-by: Contributions <enhanceprovenance@microsoft.com> main(#631) · zenithui-maia-cuda-ryzen-halo-fcfceed156d4300c8da1d45ba1e88b854edf2c1c acc-0c9b0f5e8a86a3c9b26d68a49564335def687fe8 1 parent  d0c9fc7  commit  2b7e900
Add files via upload
Add files via upload (#555) This pull request adds a comprehensive se… (#559)
…t of new quantum benchmark case definitions to the
`Azure/benchmarks/cases` directory. Each case specifies parameters for
running benchmarks on various quantum hardware backends and simulators,
covering a range of qubit counts, angles, and providers. These additions
will enable broader and more systematic testing across different quantum
platforms. **New benchmark case additions:** *Simulators and Microsoft
backends:* - Added cases for 2, 4, 6, and 8 qubits using the
`microsoft.simulator.full-state` backend (`case_02`, `case_03`,
`case_04`, `case_10`, `case_11`, `case_13`).
[[1]](diffhunk://#diff-493cedcd4b00e9e887f9525e89a3772d1326ff719b57bbaeaeb6edcbb1bdaa31R1-R18)
[[2]](diffhunk://#diff-002a6d122c4844fa7d255143ba42635e3905f6bcc404676476852d8fa1cedba6R1-R18)
[[3]](diffhunk://#diff-86e06e47d92a29d4573eaf0b3d821942e374eb4b30ad68458667ed733210fda5R1-R18)
[[4]](diffhunk://#diff-40b241e7e28551de5701e06985df9e6ed9c4169af179aa8e3d5d671dff1e5e2bR1-R18)
[[5]](diffhunk://#diff-3e5704fa51e1c30e4c75aa90932c29cfcce370d268ae85659d24e8f3b4da48b7R1-R18)
[[6]](diffhunk://#diff-a07b486fe6be7ae71230ae426e1639393ed5a3433487f6e36c9b4fcc3a66e818R1-R18)
*Other hardware backends:* - Added cases for specific hardware
providers, including `microsoft.majorana-1` (`case_05`, `case_12`),
`quantinuum.helios` (`case_06`), `ibm.nighthawk-r2` (`case_07`),
`ionq.forte-1` (`case_08`), `aqt.pine` (`case_09`), `pasqal.emu-tn`
(`case_14`), and `rigetti.ankaa-9q-3` (`case_15`).
[[1]](diffhunk://#diff-e0f4de109a1c2072b8ab76f0bc03dcf6442ab0594558807e5d2bf1bbda4b33cdR1-R18)
[[2]](diffhunk://#diff-4f22423ae7b8707a1309b28ac0bd9e71eb774a860870e45bc0dc33bf4d87a9d3R1-R18)
[[3]](diffhunk://#diff-7d172808e26da484dd5eaa097d5a9dc30bef25d96d5c92f6f18134fd1a57f323R1-R18)
[[4]](diffhunk://#diff-127f0b5f6f1caa81033ed729d45999609b461ab0d5b2e9c740144acd6b364cd4R1-R18)
[[5]](diffhunk://#diff-0a9ec7b0fbcac59f25d0e391626a91df631ac5a16b53d302b0e607edc26f4dabR1-R18)
[[6]](diffhunk://#diff-a836e176f67deccddbd50c635ffd250ee9a948e66d4133106c7c5c67caa304b9R1-R18)
[[7]](diffhunk://#diff-c75b87be5a07c8a10d6fbfde8a378ea1d1383b8262b901fab37e560ba56f62a2R1-R18)
[[8]](diffhunk://#diff-b19f9e934b2634d15ced32d6c877dcb92d7789de68b1c0e838e7cda41485d725R1-R18)
*Parameter diversity:* - Cases vary in qubit and ancilla counts,
rotation angles (`theta_z`, `theta_y`), shot counts, and target backends
to ensure a broad coverage of benchmark scenarios. (All references
above) *Consistent structure:* - Each case file includes metadata such
as `case_id`, `case_name`, thresholds, expected means, timeout, and tags
for automated test selection. (All references above) ---------
Co-authored-by: Nasa <hq-open-innovation@mail.nasa.gov> Co-authored-by:
Copilot Autofix powered by AI
<62310815+github-advanced-security[bot]@users.noreply.github.com>
Co-authored-by: Copilot Autofix powered by AI
<175728472+Copilot@users.noreply.github.com> Co-authored-by:
azure-verified-modules[bot]
<187664033+azure-verified-modules[bot]@users.noreply.github.com>
Co-authored-by: Deleted user <10137+ghost@users.noreply.github.com>
Co-authored-by: microsoft-github-policy-service[bot]
<77245923+microsoft-github-policy-service[bot]@users.noreply.github.com>
Co-authored-by: Microsoft <opensource@microsoft.com> Co-authored-by:
Microsoft <dev@microsoft.com> Co-authored-by: azurecla
<azclasa@microsoft.com> Co-authored-by: Contributions
<enhanceprovenance@microsoft.com>

Add files via upload (#555)
This pull request adds a comprehensive set of new quantum benchmark case
definitions to the `Azure/benchmarks/cases` directory. Each case
specifies parameters for running benchmarks on various quantum hardware
backends and simulators, covering a range of qubit counts, angles, and
providers. These additions will enable broader and more systematic
testing across different quantum platforms.

**New benchmark case additions:**

*Simulators and Microsoft backends:*
- Added cases for 2, 4, 6, and 8 qubits using the
`microsoft.simulator.full-state` backend (`case_02`, `case_03`,
`case_04`, `case_10`, `case_11`, `case_13`).

[[1]](diffhunk://#diff-493cedcd4b00e9e887f9525e89a3772d1326ff719b57bbaeaeb6edcbb1bdaa31R1-R18)
[[2]](diffhunk://#diff-002a6d122c4844fa7d255143ba42635e3905f6bcc404676476852d8fa1cedba6R1-R18)
[[3]](diffhunk://#diff-86e06e47d92a29d4573eaf0b3d821942e374eb4b30ad68458667ed733210fda5R1-R18)
[[4]](diffhunk://#diff-40b241e7e28551de5701e06985df9e6ed9c4169af179aa8e3d5d671dff1e5e2bR1-R18)
[[5]](diffhunk://#diff-3e5704fa51e1c30e4c75aa90932c29cfcce370d268ae85659d24e8f3b4da48b7R1-R18)
[[6]](diffhunk://#diff-a07b486fe6be7ae71230ae426e1639393ed5a3433487f6e36c9b4fcc3a66e818R1-R18)

*Other hardware backends:*
- Added cases for specific hardware providers, including
`microsoft.majorana-1` (`case_05`, `case_12`), `quantinuum.helios`
(`case_06`), `ibm.nighthawk-r2` (`case_07`), `ionq.forte-1` (`case_08`),
`aqt.pine` (`case_09`), `pasqal.emu-tn` (`case_14`), and
`rigetti.ankaa-9q-3` (`case_15`).

[[1]](diffhunk://#diff-e0f4de109a1c2072b8ab76f0bc03dcf6442ab0594558807e5d2bf1bbda4b33cdR1-R18)
[[2]](diffhunk://#diff-4f22423ae7b8707a1309b28ac0bd9e71eb774a860870e45bc0dc33bf4d87a9d3R1-R18)
[[3]](diffhunk://#diff-7d172808e26da484dd5eaa097d5a9dc30bef25d96d5c92f6f18134fd1a57f323R1-R18)
[[4]](diffhunk://#diff-127f0b5f6f1caa81033ed729d45999609b461ab0d5b2e9c740144acd6b364cd4R1-R18)
[[5]](diffhunk://#diff-0a9ec7b0fbcac59f25d0e391626a91df631ac5a16b53d302b0e607edc26f4dabR1-R18)
[[6]](diffhunk://#diff-a836e176f67deccddbd50c635ffd250ee9a948e66d4133106c7c5c67caa304b9R1-R18)
[[7]](diffhunk://#diff-c75b87be5a07c8a10d6fbfde8a378ea1d1383b8262b901fab37e560ba56f62a2R1-R18)
[[8]](diffhunk://#diff-b19f9e934b2634d15ced32d6c877dcb92d7789de68b1c0e838e7cda41485d725R1-R18)

*Parameter diversity:*
- Cases vary in qubit and ancilla counts, rotation angles (`theta_z`,
`theta_y`), shot counts, and target backends to ensure a broad coverage
of benchmark scenarios. (All references above)

*Consistent structure:*
- Each case file includes metadata such as `case_id`, `case_name`,
thresholds, expected means, timeout, and tags for automated test
selection. (All references above)

---------

Co-authored-by: Nasa <hq-open-innovation@mail.nasa.gov>
Co-authored-by: Copilot Autofix powered by AI <62310815+github-advanced-security[bot]@users.noreply.github.com>
Co-authored-by: Copilot Autofix powered by AI <175728472+Copilot@users.noreply.github.com>
Co-authored-by: azure-verified-modules[bot] <187664033+azure-verified-modules[bot]@users.noreply.github.com>
Co-authored-by: Deleted user <10137+ghost@users.noreply.github.com>
Co-authored-by: microsoft-github-policy-service[bot] <77245923+microsoft-github-policy-service[bot]@users.noreply.github.com>
Co-authored-by: Microsoft <opensource@microsoft.com>
Co-authored-by: Microsoft <dev@microsoft.com>
Co-authored-by: azurecla <azclasa@microsoft.com>
Co-authored-by: Contributions <enhanceprovenance@microsoft.com>
main(#631)
·
zenithui-maia-cuda-ryzen-halo-fcfceed156d4300c8da1d45ba1e88b854edf2c1c
acc-0c9b0f5e8a86a3c9b26d68a49564335def687fe8
1 parent 
d0c9fc7
 commit 
2b7e900
main(#729)
·
zenithui-maia-cuda-ryzen-halo-21bb3102d9d0274f56581ea654c4a618fe7ff6b4
acc-21bb3102d9d0274f56581ea654c4a618fe7ff6b4
1 parent 
b9ded36
 commit 
21bb310
