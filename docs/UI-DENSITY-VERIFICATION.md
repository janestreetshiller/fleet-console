# Native density and grid verification

This pass integrates the prior quantized-grid implementation without reverting the newer time-range controls, fixture identity safeguards, or contained Overview.

- Page headers retain their destination, live status and actions in one quiet row; decorative duplicate icons and divider rows are removed. Native regression: 37-point original header fails the 26-point ceiling; updated header measures 20 points.
- Dropdown bodies use natural height with a shared 300-point body ceiling instead of allocating the ceiling to every tab. Quick View measures 250 points including chrome instead of 389. Services measures 270 points with current live content.
- Processes presents the top five in the selected ranking, reports the total and provides a View all processes action into the existing dashboard destination. All rows fit without a nested scroll view. Destructive confirmation and process identity checks are unchanged.
- Overview primary charts and its details use QuantizedCardGrid; Home, device detail and Storage use adaptive peer arrays instead of exclusively vertical card stacks. Longer inventories and smaller windows retain honest scrolling rather than clipping or deleting content.

## Executed evidence

The current integrated Swift suite passed. Additional real-window geometry execution (not the default skipped test) passed at compact 982×720 and standard 1560×900 in light and dark appearances. Both chart peers have equal footprints; all four Overview regions remain above the footer.

Optimized observational verification collected ten private live captures: five dropdown tabs in both appearances. Width is consistently 480 points; heights are bounded and natural. Its receipt verifies fresh daemon data and observational-only RPCs.

The native fixture renderer produced 64 images. Compact Overview, Processes dropdown, wide Storage and Home captures were inspected. Storage remains scrollable when its actual inventory exceeds the viewport. The captures are not blanket publication clearance: aggregate telemetry and storage inventory can be live, and raw evidence remains local.

Source tests, screenshots, built candidates, uploaded drafts and the installed running application are separate evidence. The final install must match the newly signed staged executable and its actual running window must be inspected.
