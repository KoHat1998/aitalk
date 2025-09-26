import 'dart:async';
import 'package:flutter/material.dart';
import 'package:percent_indicator/percent_indicator.dart'; // For progress bars
// import 'package:video_player/video_player.dart'; // Import if/when you add video

// Assuming your models are here and imported in NewsScreen,
// if not, you'd import them directly:
import '../../models/stories_model.dart';


class StoryViewScreen extends StatefulWidget {
  final List<UserStoryGroup> storyGroups;
  final int initialGroupIndex;

  const StoryViewScreen({
    super.key,
    required this.storyGroups,
    required this.initialGroupIndex,
  });

  @override
  State<StoryViewScreen> createState() => _StoryViewScreenState();
}

class _StoryViewScreenState extends State<StoryViewScreen> with TickerProviderStateMixin {
  late PageController _usersPageController; // For swiping between users
  PageController? _storiesPageController;    // For swiping between stories of current user

  // Animation controllers for progress bars
  Map<int, List<AnimationController>> _storyProgressControllers = {};
  Map<int, List<double>> _storyProgressValues = {}; // To store progress for each story

  int _currentUserGroupIndex = 0;
  int _currentStoryIndex = 0;

  Timer? _storyTimer;
  static const Duration _storyDuration = Duration(seconds: 5); // How long each story shows

  // VideoPlayerController? _videoController; // For video stories

  @override
  void initState() {
    super.initState();
    _currentUserGroupIndex = widget.initialGroupIndex;
    _usersPageController = PageController(initialPage: _currentUserGroupIndex);

    _setupStoryControllersForCurrentUserGroup();
    _startStoryTimer();
  }

  void _setupStoryControllersForCurrentUserGroup() {
    _storiesPageController?.dispose(); // Dispose previous if any
    _storiesPageController = PageController(initialPage: _currentStoryIndex);

    final currentGroup = widget.storyGroups[_currentUserGroupIndex];
    if (!_storyProgressControllers.containsKey(_currentUserGroupIndex)) {
      _storyProgressControllers[_currentUserGroupIndex] = List.generate(
        currentGroup.stories.length,
            (index) => AnimationController(
          vsync: this,
          duration: _storyDuration,
        )..addListener(() {
          setState(() {
            // Update progress for the specific story
            if (_storyProgressValues[_currentUserGroupIndex] != null &&
                _storyProgressValues[_currentUserGroupIndex]!.length > index) {
              _storyProgressValues[_currentUserGroupIndex]![index] =
                  _storyProgressControllers[_currentUserGroupIndex]![index].value;
            }
          });
        })..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _nextStory();
          }
        }),
      );
      _storyProgressValues[_currentUserGroupIndex] = List.filled(currentGroup.stories.length, 0.0);
    }
    // _initializeMedia(); // Call this here if you also handle videos
  }

  void _startStoryTimer() {
    _stopStoryTimer(); // Ensure any existing timer is stopped
    // Start animation for the current story
    if (_storyProgressControllers.isNotEmpty &&
        _storyProgressControllers[_currentUserGroupIndex] != null &&
        _storyProgressControllers[_currentUserGroupIndex]!.length > _currentStoryIndex) {
      _storyProgressControllers[_currentUserGroupIndex]![_currentStoryIndex].forward(from: 0.0);
    }
    // Fallback timer if animation controller isn't ready or fails (less ideal)
    // _storyTimer = Timer(_storyDuration, _nextStory);
  }

  void _stopStoryTimer() {
    _storyTimer?.cancel();
    if (_storyProgressControllers.isNotEmpty &&
        _storyProgressControllers[_currentUserGroupIndex] != null &&
        _storyProgressControllers[_currentUserGroupIndex]!.length > _currentStoryIndex &&
        _storyProgressControllers[_currentUserGroupIndex]![_currentStoryIndex].isAnimating) {
      _storyProgressControllers[_currentUserGroupIndex]![_currentStoryIndex].stop();
    }
  }

  void _pauseStory() {
    _stopStoryTimer();
    // if (_videoController?.value.isPlaying ?? false) _videoController?.pause();
  }

  void _resumeStory() {
    // Only resume if not at the end of progress
    if (_storyProgressControllers.isNotEmpty &&
        _storyProgressControllers[_currentUserGroupIndex] != null &&
        _storyProgressControllers[_currentUserGroupIndex]!.length > _currentStoryIndex) {

      final controller = _storyProgressControllers[_currentUserGroupIndex]![_currentStoryIndex];
      if (controller.value < 1.0) { // Only forward if not completed
        controller.forward();
      } else if (controller.value == 1.0 && controller.status == AnimationStatus.completed) {
        // If it was already completed (e.g. by fast tapping), and we tapped to resume, move to next
        _nextStory();
      }
    }
    // if (_videoController?.value.isInitialized ?? false) _videoController?.play();
  }


  void _nextStory() {
    _stopStoryTimer();
    final currentGroup = widget.storyGroups[_currentUserGroupIndex];
    if (_currentStoryIndex < currentGroup.stories.length - 1) {
      setState(() {
        // Mark current story as completed for progress bar
        if (_storyProgressControllers[_currentUserGroupIndex]![_currentStoryIndex].status != AnimationStatus.completed) {
          _storyProgressControllers[_currentUserGroupIndex]![_currentStoryIndex].value = 1.0;
        }
        _currentStoryIndex++;
      });
      _storiesPageController?.animateToPage(
        _currentStoryIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeIn,
      );
      // _initializeMedia(); // For next story (image/video)
      _startStoryTimer();
    } else {
      _nextUserGroup();
    }
  }

  void _previousStory() {
    _stopStoryTimer();
    if (_currentStoryIndex > 0) {
      setState(() {
        // Reset progress for previous stories in the current group
        _storyProgressControllers[_currentUserGroupIndex]![_currentStoryIndex].value = 0.0;
        _currentStoryIndex--;
        _storyProgressControllers[_currentUserGroupIndex]![_currentStoryIndex].value = 0.0;

      });
      _storiesPageController?.animateToPage(
        _currentStoryIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeIn,
      );
      // _initializeMedia();
      _startStoryTimer();
    } else {
      _previousUserGroup();
    }
  }

  void _nextUserGroup() {
    if (_currentUserGroupIndex < widget.storyGroups.length - 1) {
      _usersPageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeIn,
      );
    } else {
      Navigator.of(context).pop(); // All stories viewed
    }
  }

  void _previousUserGroup() {
    if (_currentUserGroupIndex > 0) {
      _usersPageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeIn,
      );
    } else {
      // Potentially pop or do nothing if already at the first user
      Navigator.of(context).pop();
    }
  }


  // void _initializeMedia() async {
  //   // Dispose previous video controller
  //   // await _videoController?.dispose();
  //   // _videoController = null;

  //   final story = widget.storyGroups[_currentUserGroupIndex].stories[_currentStoryIndex];
  //   if (story.mediaType == 'video') {
  //     // _videoController = VideoPlayerController.networkUrl(Uri.parse(story.mediaUrl))
  //     //   ..initialize().then((_) {
  //     //     setState(() {}); // Update UI when video is initialized
  //     //     if (ModalRoute.of(context)?.isCurrent ?? false) { // Only play if screen is active
  //     //        _videoController?.play();
  //     //        _videoController?.setLooping(false); // Play once
  //                 // _storyProgressControllers[_currentUserGroupIndex]![_currentStoryIndex].duration = _videoController!.value.duration;
  //                 // _startStoryTimer(); // Re-start timer with video duration
  //     //     }
  //     //   }).catchError((error){
  //     //       print("Video init error: $error");
  //     //       _nextStory(); // Skip problematic video
  //     //   });
  //   } else {
        //_startStoryTimer(); // For images
  //   }
  // }


  @override
  void dispose() {
    _stopStoryTimer();
    _usersPageController.dispose();
    _storiesPageController?.dispose();
    _storyProgressControllers.forEach((_, controllers) {
      for (var controller in controllers) {
        controller.dispose();
      }
    });
    // _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.storyGroups.isEmpty) {
      return const Scaffold(body: Center(child: Text("No stories to display.")));
    }
    final UserStoryGroup currentGroup = widget.storyGroups[_currentUserGroupIndex];
    final StoryItem currentStory = currentGroup.stories.isNotEmpty && _currentStoryIndex < currentGroup.stories.length
        ? currentGroup.stories[_currentStoryIndex]
        : StoryItem(id: '', mediaUrl: '', mediaType: '', createdAt: DateTime.now()); // Fallback

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: (details) => _pauseStory(), // Pause on tap down
        onTapUp: (details) { // Handle tap up for next/prev or resume
          final screenWidth = MediaQuery.of(context).size.width;
          if (details.localPosition.dx < screenWidth * 0.3) {
            _previousStory();
          } else if (details.localPosition.dx > screenWidth * 0.7) {
            _nextStory();
          } else {
            _resumeStory(); // If tapped in the middle, resume
          }
        },
        onLongPressStart: (_) => _pauseStory(),
        onLongPressEnd: (_) => _resumeStory(),
        child: Stack(
          children: [
            // PageView for Users
            PageView.builder(
              controller: _usersPageController,
              itemCount: widget.storyGroups.length,
              onPageChanged: (userIndex) {
                _stopStoryTimer();
                // Mark all stories of previous user as seen for progress bars
                if (_storyProgressControllers.containsKey(_currentUserGroupIndex)) {
                  _storyProgressControllers[_currentUserGroupIndex]!.forEach((controller) {
                    if(controller.status != AnimationStatus.completed) controller.value = 1.0; // Mark as seen
                  });
                }
                setState(() {
                  _currentUserGroupIndex = userIndex;
                  _currentStoryIndex = 0; // Reset to first story of new user
                });
                _setupStoryControllersForCurrentUserGroup();
                _startStoryTimer();
              },
              itemBuilder: (context, userIndex) {
                final group = widget.storyGroups[userIndex];
                // Inner PageView for stories of the current user
                // We're not using a PageView here for individual stories to better control with animation
                // but the _storiesPageController could be used if preferred.
                // For now, we manually update the content based on _currentStoryIndex.
                if (group.stories.isEmpty) {
                  return const Center(child: Text("This user has no stories.", style: TextStyle(color: Colors.white)));
                }
                // Ensure _currentStoryIndex is valid for the current group after user swipe
                int storyIdxToShow = (userIndex == _currentUserGroupIndex) ? _currentStoryIndex : 0;
                if (storyIdxToShow >= group.stories.length) storyIdxToShow = group.stories.length - 1;
                if (storyIdxToShow < 0) storyIdxToShow = 0;

                final storyItem = group.stories[storyIdxToShow];

                return Center( // To display the current story
                  child: storyItem.mediaType == 'image'
                      ? Image.network(
                    storyItem.mediaUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(child: CircularProgressIndicator(color: Colors.white));
                    },
                    errorBuilder: (context, error, stackTrace) =>
                    const Center(child: Icon(Icons.error_outline, color: Colors.white, size: 50)),
                  )
                      : Center(child: Text("Video playback not yet implemented: ${storyItem.mediaUrl}", style: TextStyle(color: Colors.white))),
                  // : (_videoController?.value.isInitialized ?? false)
                  //     ? AspectRatio(
                  //         aspectRatio: _videoController!.value.aspectRatio,
                  //         child: VideoPlayer(_videoController!),
                  //       )
                  //     : const Center(child: CircularProgressIndicator(color: Colors.white)),
                );
              },
            ),

            // Overlays (Progress Bars, User Info, Close Button)
            Positioned(
              top: 40.0, // Status bar height approx
              left: 8.0,
              right: 8.0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Progress Bars
                  Row(
                    children: List.generate(currentGroup.stories.length, (index) {
                      double progress = 0.0;
                      if (_storyProgressValues.containsKey(_currentUserGroupIndex) &&
                          _storyProgressValues[_currentUserGroupIndex]!.length > index) {
                        progress = _storyProgressValues[_currentUserGroupIndex]![index];
                      } else if (index < _currentStoryIndex) {
                        progress = 1.0; // Mark previous stories as seen
                      }


                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2.0),
                          child: LinearPercentIndicator(
                            percent: progress,
                            lineHeight: 3.0,
                            backgroundColor: Colors.white.withOpacity(0.5),
                            progressColor: Colors.white,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 8.0),
                  // User Info and Close Button
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundImage: currentGroup.userAvatarUrl != null && currentGroup.userAvatarUrl!.isNotEmpty
                            ? NetworkImage(currentGroup.userAvatarUrl!)
                            : null,
                        child: (currentGroup.userAvatarUrl == null || currentGroup.userAvatarUrl!.isEmpty)
                            ? Text(currentGroup.userName.isNotEmpty ? currentGroup.userName[0].toUpperCase() : "U", style: TextStyle(color: Colors.black))
                            : null,
                        backgroundColor: Colors.white,
                      ),
                      const SizedBox(width: 8.0),
                      Text(
                        currentGroup.userName,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 28),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  if (currentStory.caption != null && currentStory.caption!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        currentStory.caption!,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
