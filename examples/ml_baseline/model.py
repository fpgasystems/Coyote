"""Models for binary classification of bitstream representations.

Available models:
  - resnet18: grayscale ResNet-18      [B, 1, 1024, 1024]
  - cnn_a:    tiny 3-layer CNN         [B, 1, 1024, 1024]
  - cnn_mid:  mid 3-layer CNN          [B, 1, 1024, 1024]
  - cnn_medium: medium 4-layer CNN     [B, 1, 1024, 1024]
  - cnn_b:    small 4-layer CNN        [B, 1, 1024, 1024]
  - cnn_mid_1d: 1D analogue of MidCNN  [B, 1, 1048576]
  - cnn_medium_1d: 1D analogue of MediumCNN [B, 1, 1048576]
  - cnn_b_1d: 1D analogue of SmallCNN  [B, 1, 1048576]
"""

import torch
import torch.nn as nn
import torchvision.models as models

from dataset import IMG_SIZE, SEQUENCE_LENGTH


# ---------------------------------------------------------------------------
# ResNet-18 (grayscale)
# ---------------------------------------------------------------------------

def grayscale_resnet18(pretrained=False):
    """Create a grayscale ResNet-18 with 1 output logit.

    Spatial shape progression for 1024x1024 input:
        Input:    [B,   1, 1024, 1024]
        conv1:    [B,  64,  512,  512]   (7x7, stride 2, pad 3)
        maxpool:  [B,  64,  256,  256]   (3x3, stride 2, pad 1)
        layer1:   [B,  64,  256,  256]
        layer2:   [B, 128,  128,  128]
        layer3:   [B, 256,   64,   64]
        layer4:   [B, 512,   32,   32]
        avgpool:  [B, 512,    1,    1]
        fc:       [B,   1]
    """
    weights = "IMAGENET1K_V1" if pretrained else None
    model = models.resnet18(weights=weights)

    old_conv1 = model.conv1
    model.conv1 = nn.Conv2d(1, 64, kernel_size=7, stride=2, padding=3, bias=False)
    if pretrained:
        with torch.no_grad():
            model.conv1.weight.copy_(old_conv1.weight.mean(dim=1, keepdim=True))

    model.fc = nn.Linear(model.fc.in_features, 1)
    return model


# ---------------------------------------------------------------------------
# CNN A — Tiny CNN (6,241 params)
# ---------------------------------------------------------------------------

class TinyCNN(nn.Module):
    """3-layer CNN for binary classification of grayscale images.

    Spatial shape progression for 1024x1024 input:
        Input:           [B,  1, 1024, 1024]
        Conv2d 7x7 s4:   [B,  8,  256,  256]
        MaxPool2d 2x2:   [B,  8,  128,  128]
        Conv2d 3x3:      [B, 16,  128,  128]
        MaxPool2d 2x2:   [B, 16,   64,   64]
        Conv2d 3x3:      [B, 32,   64,   64]
        AdaptiveAvgPool: [B, 32,    1,    1]
        Linear:          [B,  1]

    Total parameters: 6,241
    """

    def __init__(self):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv2d(1, 8, kernel_size=7, stride=4, padding=3),
            nn.ReLU(),
            nn.MaxPool2d(2, 2),
            nn.Conv2d(8, 16, kernel_size=3, stride=1, padding=1),
            nn.ReLU(),
            nn.MaxPool2d(2, 2),
            nn.Conv2d(16, 32, kernel_size=3, stride=1, padding=1),
            nn.ReLU(),
            nn.AdaptiveAvgPool2d((1, 1)),
        )
        self.fc = nn.Linear(32, 1)

    def forward(self, x):
        x = self.features(x)
        x = x.flatten(1)
        return self.fc(x)


# ---------------------------------------------------------------------------
# CNN B — Small CNN (60,545 params)
# ---------------------------------------------------------------------------

class SmallCNN(nn.Module):
    """4-layer CNN for binary classification of grayscale images.

    Spatial shape progression for 1024x1024 input:
        Input:           [B,  1, 1024, 1024]
        Conv2d 5x5 s2:   [B, 16,  512,  512]
        MaxPool2d 2x2:   [B, 16,  256,  256]
        Conv2d 3x3:      [B, 32,  256,  256]
        MaxPool2d 2x2:   [B, 32,  128,  128]
        Conv2d 3x3:      [B, 64,  128,  128]
        MaxPool2d 2x2:   [B, 64,   64,   64]
        Conv2d 3x3:      [B, 64,   64,   64]
        AdaptiveAvgPool: [B, 64,    1,    1]
        Linear:          [B,  1]

    Total parameters: 60,545
    """

    def __init__(self):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv2d(1, 16, kernel_size=5, stride=2, padding=2),
            nn.ReLU(),
            nn.MaxPool2d(2, 2),
            nn.Conv2d(16, 32, kernel_size=3, stride=1, padding=1),
            nn.ReLU(),
            nn.MaxPool2d(2, 2),
            nn.Conv2d(32, 64, kernel_size=3, stride=1, padding=1),
            nn.ReLU(),
            nn.MaxPool2d(2, 2),
            nn.Conv2d(64, 64, kernel_size=3, stride=1, padding=1),
            nn.ReLU(),
            nn.AdaptiveAvgPool2d((1, 1)),
        )
        self.fc = nn.Linear(64, 1)

    def forward(self, x):
        x = self.features(x)
        x = x.flatten(1)
        return self.fc(x)


# ---------------------------------------------------------------------------
# CNN Mid — Mid 3-layer CNN
# ---------------------------------------------------------------------------

class MidCNN(nn.Module):
    """3-layer CNN between TinyCNN and SmallCNN.

    Spatial shape progression for 1024x1024 input:
        Input:           [B,  1, 1024, 1024]
        Conv2d 5x5 s2:   [B, 12,  512,  512]
        MaxPool2d 2x2:   [B, 12,  256,  256]
        Conv2d 3x3:      [B, 24,  256,  256]
        MaxPool2d 2x2:   [B, 24,  128,  128]
        Conv2d 3x3:      [B, 48,  128,  128]
        MaxPool2d 2x2:   [B, 48,   64,   64]
        AdaptiveAvgPool: [B, 48,    1,    1]
        Linear:          [B,  1]

    Total parameters: 13,393
    """

    def __init__(self):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv2d(1, 12, kernel_size=5, stride=2, padding=2),
            nn.ReLU(inplace=True),
            nn.MaxPool2d(kernel_size=2, stride=2),
            nn.Conv2d(12, 24, kernel_size=3, stride=1, padding=1),
            nn.ReLU(inplace=True),
            nn.MaxPool2d(kernel_size=2, stride=2),
            nn.Conv2d(24, 48, kernel_size=3, stride=1, padding=1),
            nn.ReLU(inplace=True),
            nn.MaxPool2d(kernel_size=2, stride=2),
            nn.AdaptiveAvgPool2d((1, 1)),
        )
        self.classifier = nn.Linear(48, 1)

    def forward(self, x):
        x = self.features(x)
        x = x.flatten(1)
        return self.classifier(x)


# ---------------------------------------------------------------------------
# CNN Medium — Medium 4-layer CNN
# ---------------------------------------------------------------------------

class MediumCNN(nn.Module):
    """4-layer CNN between MidCNN and SmallCNN.

    Spatial shape progression for 1024x1024 input:
        Input:           [B,  1, 1024, 1024]
        Conv2d 5x5 s2:   [B, 12,  512,  512]
        MaxPool2d 2x2:   [B, 12,  256,  256]
        Conv2d 3x3:      [B, 24,  256,  256]
        MaxPool2d 2x2:   [B, 24,  128,  128]
        Conv2d 3x3:      [B, 48,  128,  128]
        MaxPool2d 2x2:   [B, 48,   64,   64]
        Conv2d 3x3:      [B, 48,   64,   64]
        AdaptiveAvgPool: [B, 48,    1,    1]
        Linear:          [B,  1]

    Total parameters: 34,153
    """

    def __init__(self):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv2d(1, 12, kernel_size=5, stride=2, padding=2),
            nn.ReLU(inplace=True),
            nn.MaxPool2d(kernel_size=2, stride=2),
            nn.Conv2d(12, 24, kernel_size=3, stride=1, padding=1),
            nn.ReLU(inplace=True),
            nn.MaxPool2d(kernel_size=2, stride=2),
            nn.Conv2d(24, 48, kernel_size=3, stride=1, padding=1),
            nn.ReLU(inplace=True),
            nn.MaxPool2d(kernel_size=2, stride=2),
            nn.Conv2d(48, 48, kernel_size=3, stride=1, padding=1),
            nn.ReLU(inplace=True),
            nn.AdaptiveAvgPool2d((1, 1)),
        )
        self.classifier = nn.Linear(48, 1)

    def forward(self, x):
        x = self.features(x)
        x = x.flatten(1)
        return self.classifier(x)


# ---------------------------------------------------------------------------
# CNN Mid 1D — Mid 3-layer 1D CNN
# ---------------------------------------------------------------------------

class MidCNN1D(nn.Module):
    """1D analogue of MidCNN for fixed-length bitstream sequences.

    Sequence length progression for 1048576-byte input:
        Input:           [B,  1, 1048576]
        Conv1d 5 s2:     [B, 12,  524288]
        MaxPool1d 2:     [B, 12,  262144]
        Conv1d 3:        [B, 24,  262144]
        MaxPool1d 2:     [B, 24,  131072]
        Conv1d 3:        [B, 48,  131072]
        MaxPool1d 2:     [B, 48,   65536]
        AdaptiveAvgPool: [B, 48,       1]
        Linear:          [B,  1]
    """

    def __init__(self):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv1d(1, 12, kernel_size=5, stride=2, padding=2),
            nn.ReLU(inplace=True),
            nn.MaxPool1d(kernel_size=2, stride=2),
            nn.Conv1d(12, 24, kernel_size=3, stride=1, padding=1),
            nn.ReLU(inplace=True),
            nn.MaxPool1d(kernel_size=2, stride=2),
            nn.Conv1d(24, 48, kernel_size=3, stride=1, padding=1),
            nn.ReLU(inplace=True),
            nn.MaxPool1d(kernel_size=2, stride=2),
            nn.AdaptiveAvgPool1d(1),
        )
        self.classifier = nn.Linear(48, 1)

    def forward(self, x):
        x = self.features(x)
        x = x.flatten(1)
        return self.classifier(x)


# ---------------------------------------------------------------------------
# CNN Medium 1D — Medium 4-layer 1D CNN
# ---------------------------------------------------------------------------

class MediumCNN1D(nn.Module):
    """1D analogue of MediumCNN for fixed-length bitstream sequences.

    Sequence length progression for 1048576-byte input:
        Input:           [B,  1, 1048576]
        Conv1d 5 s2:     [B, 12,  524288]
        MaxPool1d 2:     [B, 12,  262144]
        Conv1d 3:        [B, 24,  262144]
        MaxPool1d 2:     [B, 24,  131072]
        Conv1d 3:        [B, 48,  131072]
        MaxPool1d 2:     [B, 48,   65536]
        Conv1d 3:        [B, 48,   65536]
        AdaptiveAvgPool: [B, 48,       1]
        Linear:          [B,  1]
    """

    def __init__(self):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv1d(1, 12, kernel_size=5, stride=2, padding=2),
            nn.ReLU(inplace=True),
            nn.MaxPool1d(kernel_size=2, stride=2),
            nn.Conv1d(12, 24, kernel_size=3, stride=1, padding=1),
            nn.ReLU(inplace=True),
            nn.MaxPool1d(kernel_size=2, stride=2),
            nn.Conv1d(24, 48, kernel_size=3, stride=1, padding=1),
            nn.ReLU(inplace=True),
            nn.MaxPool1d(kernel_size=2, stride=2),
            nn.Conv1d(48, 48, kernel_size=3, stride=1, padding=1),
            nn.ReLU(inplace=True),
            nn.AdaptiveAvgPool1d(1),
        )
        self.classifier = nn.Linear(48, 1)

    def forward(self, x):
        x = self.features(x)
        x = x.flatten(1)
        return self.classifier(x)


# ---------------------------------------------------------------------------
# CNN B 1D — Small 4-layer 1D CNN
# ---------------------------------------------------------------------------

class SmallCNN1D(nn.Module):
    """1D analogue of SmallCNN for fixed-length bitstream sequences.

    Sequence length progression for 1048576-byte input:
        Input:           [B,  1, 1048576]
        Conv1d 5 s2:     [B, 16,  524288]
        MaxPool1d 2:     [B, 16,  262144]
        Conv1d 3:        [B, 32,  262144]
        MaxPool1d 2:     [B, 32,  131072]
        Conv1d 3:        [B, 64,  131072]
        MaxPool1d 2:     [B, 64,   65536]
        Conv1d 3:        [B, 64,   65536]
        AdaptiveAvgPool: [B, 64,       1]
        Linear:          [B,  1]
    """

    def __init__(self):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv1d(1, 16, kernel_size=5, stride=2, padding=2),
            nn.ReLU(),
            nn.MaxPool1d(2, 2),
            nn.Conv1d(16, 32, kernel_size=3, stride=1, padding=1),
            nn.ReLU(),
            nn.MaxPool1d(2, 2),
            nn.Conv1d(32, 64, kernel_size=3, stride=1, padding=1),
            nn.ReLU(),
            nn.MaxPool1d(2, 2),
            nn.Conv1d(64, 64, kernel_size=3, stride=1, padding=1),
            nn.ReLU(),
            nn.AdaptiveAvgPool1d(1),
        )
        self.fc = nn.Linear(64, 1)

    def forward(self, x):
        x = self.features(x)
        x = x.flatten(1)
        return self.fc(x)


# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------

MODEL_SPECS = {
    "resnet18": {
        "representation": "2d",
        "default_target_layer": "layer4.1.conv2",
    },
    "cnn_a": {
        "representation": "2d",
        "default_target_layer": "features.6",
    },
    "cnn_mid": {
        "representation": "2d",
        "default_target_layer": "features.6",
    },
    "cnn_medium": {
        "representation": "2d",
        "default_target_layer": "features.9",
    },
    "cnn_mid_1d": {
        "representation": "1d",
        "default_target_layer": "features.6",
    },
    "cnn_medium_1d": {
        "representation": "1d",
        "default_target_layer": "features.9",
    },
    "cnn_b": {
        "representation": "2d",
        "default_target_layer": "features.9",
    },
    "cnn_b_1d": {
        "representation": "1d",
        "default_target_layer": "features.9",
    },
}

MODEL_CHOICES = list(MODEL_SPECS.keys())


def get_model_spec(name):
    try:
        return MODEL_SPECS[name]
    except KeyError as exc:
        raise ValueError(
            f"Unknown model: {name!r}. Choose from {MODEL_CHOICES}"
        ) from exc


def build_model(name):
    """Build a model by name. Returns an nn.Module with [B,1] output."""
    if name == "resnet18":
        return grayscale_resnet18(pretrained=False)
    elif name == "cnn_a":
        return TinyCNN()
    elif name == "cnn_mid":
        return MidCNN()
    elif name == "cnn_medium":
        return MediumCNN()
    elif name == "cnn_mid_1d":
        return MidCNN1D()
    elif name == "cnn_medium_1d":
        return MediumCNN1D()
    elif name == "cnn_b":
        return SmallCNN()
    elif name == "cnn_b_1d":
        return SmallCNN1D()
    else:
        raise ValueError(f"Unknown model: {name!r}. Choose from {MODEL_CHOICES}")


def test_forward_pass():
    """Verify all models run with a dummy input of the expected shape."""
    for name in MODEL_CHOICES:
        spec = get_model_spec(name)
        model = build_model(name)
        model.eval()
        if spec["representation"] == "1d":
            x = torch.randn(2, 1, SEQUENCE_LENGTH)
        else:
            x = torch.randn(2, 1, IMG_SIZE, IMG_SIZE)
        with torch.no_grad():
            out = model(x)
        n_params = sum(p.numel() for p in model.parameters())
        print(
            f"{name:10s}: input={tuple(x.shape)} output={out.shape} "
            f"params={n_params:,}"
        )
        assert out.shape == (2, 1), f"Expected (2, 1), got {out.shape}"
    print("All forward passes OK")


if __name__ == "__main__":
    test_forward_pass()
