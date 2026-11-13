package main

import yamlv3 "go.yaml.in/yaml/v3"

// Some panel serializers emit indexed/named objects where Clash requires a
// sequence. Only normalize known collection fields; native validation still
// rejects malformed entries and unsupported proxy options afterwards.
func normalizeProfileCollections(data []byte) []byte {
	var document yamlv3.Node
	if yamlv3.Unmarshal(data, &document) != nil || len(document.Content) != 1 {
		return data
	}
	root := document.Content[0]
	if root.Kind != yamlv3.MappingNode {
		return data
	}
	changed := false
	for i := 0; i+1 < len(root.Content); i += 2 {
		switch root.Content[i].Value {
		case "proxies", "proxy-groups", "listeners":
			value := root.Content[i+1]
			if converted := profileCollectionSequence(value); converted != nil {
				root.Content[i+1] = converted
				changed = true
			}
		}
	}
	if !changed {
		return data
	}
	encoded, err := yamlv3.Marshal(&document)
	if err != nil {
		return data
	}
	return encoded
}

func profileMappingValue(node *yamlv3.Node, key string) *yamlv3.Node {
	for i := 0; i+1 < len(node.Content); i += 2 {
		if node.Content[i].Value == key {
			return node.Content[i+1]
		}
	}
	return nil
}

func profileCollectionSequence(value *yamlv3.Node) *yamlv3.Node {
	if value.Kind != yamlv3.MappingNode {
		return nil
	}
	sequence := &yamlv3.Node{
		Kind: yamlv3.SequenceNode, Tag: "!!seq",
		Anchor: value.Anchor, HeadComment: value.HeadComment,
		LineComment: value.LineComment, FootComment: value.FootComment,
	}
	// A single proxy/group object can be represented as a one-element sequence.
	name, kind := profileMappingValue(value, "name"), profileMappingValue(value, "type")
	if name != nil && name.Kind == yamlv3.ScalarNode && kind != nil && kind.Kind == yamlv3.ScalarNode {
		entry := *value
		entry.Anchor = ""
		sequence.Content = []*yamlv3.Node{&entry}
		return sequence
	}
	for i := 0; i+1 < len(value.Content); i += 2 {
		key, entry := value.Content[i], value.Content[i+1]
		if entry.Kind != yamlv3.MappingNode {
			return nil
		}
		copyEntry := *entry
		if profileMappingValue(entry, "name") == nil {
			// Numeric PHP array indexes are not node names.
			if key.Kind != yamlv3.ScalarNode || key.Tag != "!!str" || key.Value == "" {
				return nil
			}
			copyEntry.Content = append([]*yamlv3.Node{
				{Kind: yamlv3.ScalarNode, Tag: "!!str", Value: "name"},
				{Kind: yamlv3.ScalarNode, Tag: "!!str", Value: key.Value},
			}, entry.Content...)
		}
		sequence.Content = append(sequence.Content, &copyEntry)
	}
	return sequence
}
